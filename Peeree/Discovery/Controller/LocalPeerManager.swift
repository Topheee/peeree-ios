//
//  LocalPeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth
import KeychainWrapper
import PeereeCore

/// Values of this type are intended to contain <code>CBCentral.identifier</code>'s only.
typealias CentralID = UUID

/// The informed party of a ``LocalPeerManager``, which handles the 'server' part of the Bluetooth communication
///
/// > Note: All methods are called from the manager's internal dispatch queue.
protocol LocalPeerManagerDelegate: AnyObject {
	/// The Bluetooth service is now being advertised, meaning the user is now visible to other people.
	func advertisingStarted()

	/// The Bluetooth service is no longer being advertised, meaning the user is not visible to other people.
	func advertisingStopped(with error: Error?)

	/// Verifying the identity of a peer that is reading our data failed.
	func authenticationFromPeerFailed(_ peerID: PeerID, with error: Error)

	/// Digitally signing at least one of the profile characteristics failed, meaning other peers won't display us.
	func characteristicSigningFailed(with error: Error)

	/// Another peer claims we have a pin match with them.
	func receivedPinMatchIndication(from peerID: PeerID)

	/// Check the validity of the `signature` for the `nonce`.
	func verify(_ peerID: PeerID, nonce: Data, signature: Data, _ result: @escaping (Bool) -> ())
}

/// The LocalPeerManager serves as delegate of the local peripheral manager to supply information about the local peer to connected peers.
///
/// > Warning: All the `CBPeripheralManagerDelegate` methods are assumed to be executed on an internal dipatch queue so you must not call them yourself!
final class LocalPeerManager: NSObject, CBPeripheralManagerDelegate {

	// Log tag.
	private static let LogTag = "LocalPeerManager"

	private let dQueue = DispatchQueue(label: "com.peeree.localpeermanager_q", qos: .utility, attributes: [])
	private let peer: Peer
	private let biography: String
	private let keyPair: KeyPair
	private let pictureResourceURL: URL
	
	private var peripheralManager: CBPeripheralManager! = nil
	
	private var interruptedTransfers: [(Data, CBMutableCharacteristic, CBCentral, Bool)] = []
	
	// unfortunenately this will grow until we go offline as we do not get any disconnection notification...
	private var _availableCentrals = [CentralID : PeerID]()
	// we authenticate only pin matched centrals, because we take the public key from the AccountController instead of verifying with the central server each time (improving user privacy and speed)
	private var authenticatedPinMatchedCentrals = [CentralID : PeerID]()
	
	private var nonces = [CentralID : Data]()
	private var remoteNonces = [PeerID : Data]()
	private var partialRemoteUUIDs = [CentralID : Data]()

	/// Informed when advertising is started/stopped or a remote peer wrote data to us.
	weak var delegate: LocalPeerManagerDelegate?

	/// Advertises the profile information to other peers.
	init(peer: Peer, biography: String, keyPair: KeyPair, pictureResourceURL: URL) {
		self.peer = peer
		self.biography = biography
		self.keyPair = keyPair
		self.pictureResourceURL = pictureResourceURL
	}

	/// Begin advertising the Bluetooth service to other device around.
	func startAdvertising() {
		dQueue.async {
			guard self.peripheralManager == nil else { return }

			self.peripheralManager = CBPeripheralManager(delegate: self, queue: self.dQueue, options: nil)
		}
	}

	/// Stop advertising the Bluetooth service to other device around.
	func stopAdvertising() {
		dQueue.async { self.abortAdvertising(with: nil) }
	}

	/// Forgets all data about the central with `identifier` equals to `cbPeerID`.
	func disconnect(_ cbPeerID: UUID) {
		dQueue.async {
			_ = self._availableCentrals.removeValue(forKey: cbPeerID)
			_ = self.authenticatedPinMatchedCentrals.removeValue(forKey: cbPeerID)
		}
	}
	
	// MARK: CBPeripheralManagerDelegate
	
//	func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
//		// both always the same
////		let services = dict[CBPeripheralManagerRestoredStateServicesKey]
////		let advertisementData = dict[CBPeripheralManagerRestoredStateAdvertisementDataKey]
//	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
		if let error = error {
			elog(Self.LogTag, "Adding service \(service.uuid.uuidString) failed (\(error.localizedDescription)). - Stopping advertising.")
			abortAdvertising(with: error)
			return
		}
		
		peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [CBUUID.PeereeServiceID]])
	}
	
	func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
		switch peripheral.state {
		case .unknown, .resetting:
			// just wait
			break
		case .unsupported, .unauthorized:
			stopAdvertising()
		case .poweredOff:
			stopAdvertising()
		case .poweredOn:
			peripheral.add(createService())
		@unknown default:
			// just wait
			break
		}
	}
	
	func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
		guard let theError = error else {
			delegate?.advertisingStarted()
			return
		}

		abortAdvertising(with: theError)
	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
		dlog(Self.LogTag, "Central \(central.identifier.uuidString.left(8)) did subscribe to \(characteristic.uuid.uuidString.left(8)). Read size: \(central.maximumUpdateValueLength).")
		switch characteristic.uuid {
		case CBUUID.BiographyCharacteristicID:
			send(data: biography.data(prefixedEncoding: biography.smallestEncoding) ?? Data(), via: peripheral, of: characteristic as! CBMutableCharacteristic, to: central, sendSize: true)
		case CBUUID.PortraitCharacteristicID:
			do {
				let data = try Data(contentsOf: pictureResourceURL)
				send(data: data, via: peripheral, of: characteristic as! CBMutableCharacteristic, to: central, sendSize: true)
			} catch {
				elog(Self.LogTag, "Failed to read user portrait: \(error.localizedDescription)")
			}
		default:
			break
		}
	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
		interruptedTransfers = interruptedTransfers.filter { (_, interruptedCharacteristic, interruptedCentral, _) -> Bool in // PERFORMANCE
			return interruptedCentral.identifier != central.identifier ||
					interruptedCharacteristic.uuid != characteristic.uuid
		}
	}
	
	func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
		// Start sending again
		guard interruptedTransfers.count > 0 else { return }
		let (data, characteristic, central, sendSize) = interruptedTransfers.removeLast()
//		dlog(Self.LogTag, "continue send \(characteristic.uuid.uuidString.left(8))")
		send(data: data, via: peripheral, of: characteristic, to: central, sendSize: sendSize)
	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
		let centralID = request.central.identifier
		dlog(Self.LogTag, "Did receive read on \(request.characteristic.uuid.uuidString.left(8)) from central \(centralID)")
		if let data = peer.getCharacteristicValue(of: request.characteristic.uuid) {
			// dead code, as we provided those values when we created the mutable characteristics
			if (request.offset >= data.count) {
				peripheral.respond(to: request, withResult: .invalidOffset)
			} else {
				request.value = data.subdata(in: request.offset..<data.count - request.offset)
				peripheral.respond(to: request, withResult: .success)
			}
		} else if request.characteristic.uuid == CBUUID.AuthenticationCharacteristicID {
			guard let nonce = nonces.removeValue(forKey: centralID) else {
				peripheral.respond(to: request, withResult: .insufficientResources)
				return
			}
			do {
				let signature = try keyPair.sign(message: nonce)
				
				if (request.offset >= signature.count) {
					peripheral.respond(to: request, withResult: .invalidOffset)
				} else {
					let subSignature = signature.subdata(in: request.offset ..< signature.count-request.offset)
					if subSignature.count < 1 {
						elog(Self.LogTag, "requested signature range is empty. Offset: \(request.offset), signature size: \(signature.count)")
						peripheral.respond(to: request, withResult: .invalidOffset)
					} else {
						request.value = subSignature
						peripheral.respond(to: request, withResult: .success)
					}
				}
			} catch {
				elog(Self.LogTag, "Signing Bluetooth nonce failed: \(error)")
				peripheral.respond(to: request, withResult: .requestNotSupported)
			}
		} else if request.characteristic.uuid == CBUUID.RemoteAuthenticationCharacteristicID {
			guard let peerID = _availableCentrals[request.central.identifier] else {
				peripheral.respond(to: request, withResult: .insufficientResources)
				return
			}
			let randomByteCount = min(request.central.maximumUpdateValueLength, keyPair.blockSize)
			do {
				var nonce = try generateRandomData(length: randomByteCount)
				remoteNonces[peerID] = nonce
				request.value = nonce
				nonce.resetBytes(in: 0..<nonce.count)
				peripheral.respond(to: request, withResult: .success)
			} catch let error {
				elog(Self.LogTag, "Generating random Bluetooth nonce failed: \(error.localizedDescription).")
				delegate?.authenticationFromPeerFailed(peerID, with: error)
				peripheral.respond(to: request, withResult: .unlikelyError)
			}
		} else if request.characteristic.uuid == CBUUID.PortraitSignatureCharacteristicID {
			// this can happen when we do not have a portrait set and thus the PortraitSignatureCharacteristicID value is `nil`
			peripheral.respond(to: request, withResult: .insufficientResources)
		} else {
			wlog(Self.LogTag, "Received unimplemented read request for characteristic: \(request.characteristic.uuid.uuidString)")
			peripheral.respond(to: request, withResult: .requestNotSupported)
		}
	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
		var error: CBATTError.Code = .success
		
		// these are the possible contents of the request
		var _peer: (PeerID, UUID)? = nil
		var _pin: (PeerID, Bool)? = nil
		var _nonce: (CBCentral, Data)? = nil
		
		for request in requests {
			dlog(Self.LogTag, "Did receive write on \(request.characteristic.uuid.uuidString.left(8)) from central \(request.central.identifier)")
			guard let data = request.value else {
				// this probably never happens
				elog(Self.LogTag, "received empty write request.")
				error = .unlikelyError
				break
			}

			if request.characteristic.uuid == CBUUID.RemoteUUIDCharacteristicID {
				var peerIDData = data
				if data.count < 36 {
					// we assume that the data is always of the form "eeb9e7f2-5442-42cc-ac91-e25e10a8d6ee"
					// or, it is chunked
					if let firstPart = partialRemoteUUIDs.removeValue(forKey: request.central.identifier) {
						// we only support a maximum of 2 chunks (because minimum update length seems to be 18 bytes, this fits exactly)
						// note that we could also check for the offset to be 18 here
						peerIDData = firstPart + data
					} else {
						partialRemoteUUIDs[request.central.identifier] = data
						break
					}
					
				}
				
				guard let peerID = PeerID(data: peerIDData) else {
					error = .insufficientResources
					break
				}
				
				_peer = (peerID, request.central.identifier)
			} else if request.characteristic.uuid == CBUUID.PinMatchIndicationCharacteristicID {
				guard let pinFlag = data.first, let peerID = _availableCentrals[request.central.identifier] else {
					error = .insufficientResources
					break
				}
				
				_pin = (peerID, pinFlag != 0)
			} else if request.characteristic.uuid == CBUUID.AuthenticationCharacteristicID {
				_nonce = (request.central, data)
			} else if request.characteristic.uuid == CBUUID.RemoteAuthenticationCharacteristicID {
				guard let peerID = _availableCentrals[request.central.identifier],
					  let nonce = remoteNonces.removeValue(forKey: peerID) else {
					error = .insufficientResources
					break
				}

				// note that we do not return the result of the verification process to the remote party
				delegate?.verify(peerID, nonce: nonce, signature: data) { verified in
					guard verified else {
						wlog(Self.LogTag, "the peer \(peerID) which did not pin match us tried to authenticate to us.")
						return
					}

					self.dQueue.async {
						self.authenticatedPinMatchedCentrals[request.central.identifier] = peerID
					}
				}
			} else {
				error = .requestNotSupported
				break
			}
		}
		if error == .success {
			if let peer = _peer {
				_availableCentrals[peer.1] = peer.0
			}
			if let (peerID, pin) = _pin, pin {
				// attack scenario: Eve sends us an indication with her or Bob's PeerID => we always validate with the server, and as we do not react to Eve directly, so Eve cannot derive sensitive information
				delegate?.receivedPinMatchIndication(from: peerID)
			}
			if let (central, nonce) = _nonce {
				nonces[central.identifier] = nonce
			}
		}
		peripheral.respond(to: requests.first!, withResult: error)
	}
	
	// MARK: Private Methods

	/// An unforeseen error prevents us from advertising; must be called on `dQueue`.
	private func abortAdvertising(with error: Error?) {
		guard let manager = peripheralManager else { return }

		manager.removeAllServices()
		manager.stopAdvertising()
		peripheralManager = nil

		self._availableCentrals.removeAll()
		self.authenticatedPinMatchedCentrals.removeAll()
		self.nonces.removeAll()
		self.interruptedTransfers.removeAll()
		self.delegate?.advertisingStopped(with: error)
	}

	/// Generate the to-be-advertised GATT service.
	private func createService() -> CBMutableService {
		// value: UserPeerManager.instance.peer.idData
		let localPeerIDCharacteristic = CBMutableCharacteristic(type: CBUUID.LocalPeerIDCharacteristicID, properties: [.read], value: peer.id.idData, permissions: [.readable])
		// value: remote peer.idData
		let remoteUUIDCharacteristic = CBMutableCharacteristic(type: CBUUID.RemoteUUIDCharacteristicID, properties: [.write], value: nil, permissions: [.writeable])
		// value: Data(count: 1)
		let pinnedCharacteristic = CBMutableCharacteristic(type: CBUUID.PinMatchIndicationCharacteristicID, properties: [.write], value: nil, permissions: [.writeable])
		// value try? Data(contentsOf: UserPeerManager.pictureResourceURL)
		let portraitCharacteristic = CBMutableCharacteristic(type: CBUUID.PortraitCharacteristicID, properties: [.indicate], value: nil, permissions: [])
		// value: aggregateData
		let aggregateCharacteristic = CBMutableCharacteristic(type: CBUUID.AggregateCharacteristicID, properties: [.read], value: peer.info.aggregateData, permissions: [.readable])
		// value: lastChangedData
		let lastChangedCharacteristic = CBMutableCharacteristic(type: CBUUID.LastChangedCharacteristicID, properties: [.read], value: peer.info.lastChangedData, permissions: [.readable])
		// value nicknameData
		let nicknameCharacteristic = CBMutableCharacteristic(type: CBUUID.NicknameCharacteristicID, properties: [.read], value: peer.info.nicknameData, permissions: [.readable])
		// value UserPeerManager.instance.peer.publicKey
		let publicKeyCharacteristic = CBMutableCharacteristic(type: CBUUID.PublicKeyCharacteristicID, properties: [.read], value: peer.id.publicKeyData, permissions: [.readable])
		// value nonce when read, signed nonce when written
		// Version 2: value with public key of peer encrypted nonce when read, signed nonce encrypted with user's public key when written
		let authCharacteristic = CBMutableCharacteristic(type: CBUUID.AuthenticationCharacteristicID, properties: [.read, .write], value: nil, permissions: [.readable, .writeable])
		// Version 2: value with public key of peer encrypted nonce when read, signed nonce encrypted with user's public key when written
		let remoteAuthCharacteristic = CBMutableCharacteristic(type: CBUUID.RemoteAuthenticationCharacteristicID, properties: [.read, .write], value: nil, permissions: [.readable, .writeable])
		// value: String.data(prefixedEncoding:)
		let biographyCharacteristic = CBMutableCharacteristic(type: CBUUID.BiographyCharacteristicID, properties: [.indicate], value: nil, permissions: [])

		// provide signature characteristics
		var peerIDSignature: Data? = nil, aggregateSignature: Data? = nil, nicknameSignature: Data? = nil, portraitSignature: Data? = nil, biographySignature: Data? = nil
		do {
			peerIDSignature = try keyPair.sign(message: peer.id.idData)
			aggregateSignature = try keyPair.sign(message: peer.info.aggregateData)
			nicknameSignature = try keyPair.sign(message: peer.info.nicknameData)
			try biography.data(prefixedEncoding: biography.smallestEncoding).map { biographySignature = try keyPair.sign(message: $0) }
			if peer.info.hasPicture {
				let imageData = try Data(contentsOf: pictureResourceURL)
				portraitSignature = try keyPair.sign(message: imageData)
			}
		} catch {
			elog(Self.LogTag, "Failed to create signature characteristics. (\(error.localizedDescription))")
			delegate?.characteristicSigningFailed(with: error)
		}

		let peerIDSignatureCharacteristic = CBMutableCharacteristic(type: CBUUID.PeerIDSignatureCharacteristicID, properties: [.read], value: peerIDSignature, permissions: [.readable])
		let portraitSignatureCharacteristic = CBMutableCharacteristic(type: CBUUID.PortraitSignatureCharacteristicID, properties: [.read], value: portraitSignature, permissions: [.readable])
		let aggregateSignatureCharacteristic = CBMutableCharacteristic(type: CBUUID.AggregateSignatureCharacteristicID, properties: [.read], value: aggregateSignature, permissions: [.readable])
		let nicknameSignatureCharacteristic = CBMutableCharacteristic(type: CBUUID.NicknameSignatureCharacteristicID, properties: [.read], value: nicknameSignature, permissions: [.readable])
		let biographySignatureCharacteristic = CBMutableCharacteristic(type: CBUUID.BiographySignatureCharacteristicID, properties: [.read], value: biographySignature, permissions: [.readable])

		let peereeService = CBMutableService(type: CBUUID.PeereeServiceID, primary: true)
		peereeService.characteristics = [localPeerIDCharacteristic, remoteUUIDCharacteristic, pinnedCharacteristic, portraitCharacteristic, aggregateCharacteristic, lastChangedCharacteristic, nicknameCharacteristic, publicKeyCharacteristic, authCharacteristic, remoteAuthCharacteristic, peerIDSignatureCharacteristic, portraitSignatureCharacteristic, aggregateSignatureCharacteristic, nicknameSignatureCharacteristic, biographyCharacteristic, biographySignatureCharacteristic]

		return peereeService
	}

	/// Synchronously transmit `data` to peer until send queue is full.
	private func send(data: Data, via peripheral: CBPeripheralManager, of characteristic: CBMutableCharacteristic, to central: CBCentral, sendSize: Bool) {
		if sendSize {
			// send the amount of bytes in data in the first package
			var size = CBCharacteristic.SplitCharacteristicSize(data.count)
			
			let sizeData = Data(bytesNoCopy: &size, count: MemoryLayout<CBCharacteristic.SplitCharacteristicSize>.size, deallocator: Data.Deallocator.none)
			guard peripheral.updateValue(sizeData, for: characteristic, onSubscribedCentrals: [central]) else {
//				dlog(Self.LogTag, "size send interrupted \(characteristic.uuid.uuidString.left(8))")
				interruptedTransfers.append((data, characteristic, central, true))
				return
			}
		}
		
		var fromIndex = data.startIndex
		var toIndex = data.index(fromIndex, offsetBy: central.maximumUpdateValueLength, limitedBy: data.endIndex) ?? data.endIndex
		
		// There's data left, so send until the callback fails, or we're done.
		
		var send = fromIndex != data.endIndex
		
		while (send) {
			// Make the next chunk
			
			// Copy out the data we want
			let chunk = data.subdata(in: fromIndex..<toIndex)
			
			// Send it
			send = peripheral.updateValue(chunk, for: characteristic, onSubscribedCentrals: [central])
			
			// If it didn't work, drop out and wait for the callback
			guard send else {
				interruptedTransfers.append((data.subdata(in: fromIndex..<data.endIndex), characteristic, central, false))
//				dlog(Self.LogTag, "data send interrupted \(characteristic.uuid.uuidString.left(8)) at \(fromIndex) of \(data.endIndex)")
				return
			}
			
			// It did send, so update our indices
			fromIndex = toIndex
			toIndex = data.index(fromIndex, offsetBy: central.maximumUpdateValueLength, limitedBy: data.endIndex) ?? data.endIndex
			
			// Was it the last one?
			send = fromIndex != data.endIndex
		}
		
		if fromIndex == data.endIndex {
			dlog(Self.LogTag, "data send truly finished \(characteristic.uuid.uuidString.left(8))")
			characteristic.value = nil
		}

		// continue to send other interrupted transfers
		peripheralManagerIsReady(toUpdateSubscribers: peripheral)
	}
}

extension Peer {
	/// Retrieves the binary data to be sent over Bluetooth for characteristics, which values are stored in a ``Peer``.
	func getCharacteristicValue(of characteristicID: CBUUID) -> Data? {
		switch characteristicID {
		case CBUUID.LocalPeerIDCharacteristicID:
			return id.idData
		case CBUUID.AggregateCharacteristicID:
			return info.aggregateData
		case CBUUID.LastChangedCharacteristicID:
			return info.lastChangedData
		case CBUUID.NicknameCharacteristicID:
			return info.nicknameData
		case CBUUID.PublicKeyCharacteristicID:
			return id.publicKeyData
		default:
			return nil
		}
	}
}
