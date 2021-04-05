//
//  LocalPeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth

/// Values of this type are intended to contain <code>CBCentral.identifier</code>'s only.
typealias CentralID = UUID

protocol LocalPeerManagerDelegate: AnyObject {
//	func networkTurnedOff()
	func advertisingStarted()
	func advertisingStopped()
	func localPeerDelegate(for peerID: PeerID) -> LocalPeerDelegate
}

protocol LocalPeerDelegate {
	func receivedPinMatchIndication()
	func received(message: String)
}

/// The LocalPeerManager singleton serves as delegate of the local peripheral manager to supply information about the local peer to connected peers.
/// All the CBPeripheralManagerDelegate methods work on a separate queue so you must not call them yourself.
final class LocalPeerManager: NSObject, CBPeripheralManagerDelegate {
	let dQueue = DispatchQueue(label: "com.peeree.localpeermanager_q", attributes: [])
	
	private var peripheralManager: CBPeripheralManager! = nil
	
	private var interruptedTransfers: [(Data, CBMutableCharacteristic, CBCentral, Bool)] = []
	
	// unfortunenately this will grow until we go offline as we do not get any disconnection notification...
	private var _availableCentrals = [CentralID : PeerID]()
	// we authenticate only pin matched centrals, because we take the public key from the AccountController instead of verifying with the central server each time (improving user privacy and speed)
	private var authenticatedPinMatchedCentrals = [CentralID : PeerID]()
	
	private var nonces = [CentralID : Data]()
	private var remoteNonces = [PeerID : Data]()
	private var partialRemoteUUIDs = [CentralID : Data]()
	
	weak var delegate: LocalPeerManagerDelegate?
	
	var isAdvertising: Bool {
//		return dQueue.sync {
			return peripheralManager != nil //&& peripheralManager.isAdvertising
//		}
	}
	
	func startAdvertising() {
		guard !isAdvertising else { return }
		
//		#if os(iOS)
//		peripheralManager = CBPeripheralManager(delegate: self, queue: dQueue, options: [CBPeripheralManagerOptionRestoreIdentifierKey : "PeripheralManager"])
//		#else
		peripheralManager = CBPeripheralManager(delegate: self, queue: dQueue, options: nil)
//		#endif
	}
	
	func stopAdvertising() {
		guard isAdvertising else { return }
		
		peripheralManager.removeAllServices()
		peripheralManager.stopAdvertising()
		peripheralManager = nil
		
		dQueue.async {
			self._availableCentrals.removeAll()
			self.nonces.removeAll()
			self.interruptedTransfers.removeAll()
			self.delegate?.advertisingStopped()
		}
	}
	
	func disconnect(_ cbPeerID: UUID) {
		dQueue.async {
			_ = self._availableCentrals.removeValue(forKey: cbPeerID)
		}
	}
	
	// MARK: CBPeripheralManagerDelegate
	
//	func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
//		// both always the same
////		let services = dict[CBPeripheralManagerRestoredStateServicesKey]
////		let advertisementData = dict[CBPeripheralManagerRestoredStateAdvertisementDataKey]
//	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
		guard error == nil else {
			NSLog("Adding service \(service.uuid.uuidString) failed (\(error!.localizedDescription)). - Stopping advertising.")
			stopAdvertising()
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
			// value: UserPeerManager.instance.peer.idData
			let localPeerIDCharacteristic = CBMutableCharacteristic(type: CBUUID.LocalPeerIDCharacteristicID, properties: [.read], value: UserPeerManager.instance.peer.idData, permissions: [.readable])
			// value: remote peer.idData
			let remoteUUIDCharacteristic = CBMutableCharacteristic(type: CBUUID.RemoteUUIDCharacteristicID, properties: [.write], value: nil, permissions: [.writeable])
			// value: Data(count: 1)
			let pinnedCharacteristic = CBMutableCharacteristic(type: CBUUID.PinMatchIndicationCharacteristicID, properties: [.write], value: nil, permissions: [.writeable])
			// value try? Data(contentsOf: UserPeerManager.pictureResourceURL)
			let portraitCharacteristic = CBMutableCharacteristic(type: CBUUID.PortraitCharacteristicID, properties: [.indicate], value: nil, permissions: [])
			// value: aggregateData
			let aggregateCharacteristic = CBMutableCharacteristic(type: CBUUID.AggregateCharacteristicID, properties: [.read], value: UserPeerManager.instance.peer.aggregateData, permissions: [.readable])
			// value: lastChangedData
			let lastChangedCharacteristic = CBMutableCharacteristic(type: CBUUID.LastChangedCharacteristicID, properties: [.read], value: UserPeerManager.instance.peer.lastChangedData, permissions: [.readable])
			// value nicknameData
			let nicknameCharacteristic = CBMutableCharacteristic(type: CBUUID.NicknameCharacteristicID, properties: [.read], value: UserPeerManager.instance.peer.nicknameData, permissions: [.readable])
			// value UserPeerManager.instance.peer.publicKey
			let publicKeyCharacteristic = CBMutableCharacteristic(type: CBUUID.PublicKeyCharacteristicID, properties: [.read], value: UserPeerManager.instance.peer.publicKeyData, permissions: [.readable])
			// value nonce when read, signed nonce when written
			// Version 2: value with public key of peer encrypted nonce when read, signed nonce encrypted with user's public key when written
			let authCharacteristic = CBMutableCharacteristic(type: CBUUID.AuthenticationCharacteristicID, properties: [.read, .write], value: nil, permissions: [.readable, .writeable])
			// Version 2: value with public key of peer encrypted nonce when read, signed nonce encrypted with user's public key when written
			let remoteAuthCharacteristic = CBMutableCharacteristic(type: CBUUID.RemoteAuthenticationCharacteristicID, properties: [.read, .write], value: nil, permissions: [.readable, .writeable])
			// value: String.data(prefixedEncoding:)
			let messageCharacteristic = CBMutableCharacteristic(type: CBUUID.MessageCharacteristicID, properties: [.write], value: nil, permissions: [.writeable])
			// value: String.data(prefixedEncoding:)
			let biographyCharacteristic = CBMutableCharacteristic(type: CBUUID.BiographyCharacteristicID, properties: [.indicate], value: nil, permissions: [])

			// provide signature characteristics
			var peerIDSignature: Data? = nil, aggregateSignature: Data? = nil, nicknameSignature: Data? = nil, portraitSignature: Data? = nil, biographySignature: Data? = nil
			do {
				peerIDSignature = try UserPeerManager.instance.keyPair.sign(message: UserPeerManager.instance.peer.idData)
				aggregateSignature = try UserPeerManager.instance.keyPair.sign(message: UserPeerManager.instance.peer.aggregateData)
				nicknameSignature = try UserPeerManager.instance.keyPair.sign(message: UserPeerManager.instance.peer.nicknameData)
				biographySignature = try UserPeerManager.instance.keyPair.sign(message: UserPeerManager.instance.peer.biographyData)
				if UserPeerManager.instance.peer.hasPicture {
					let imageData = try Data(contentsOf: UserPeerManager.pictureResourceURL)
					portraitSignature = try UserPeerManager.instance.keyPair.sign(message: imageData)
				}
			} catch {
				NSLog("ERROR: Failed to create signature characteristics. (\(error.localizedDescription))")
			}
			let peerIDSignatureCharacteristic = CBMutableCharacteristic(type: CBUUID.PeerIDSignatureCharacteristicID, properties: [.read], value: peerIDSignature, permissions: [.readable])
			let portraitSignatureCharacteristic = CBMutableCharacteristic(type: CBUUID.PortraitSignatureCharacteristicID, properties: [.read], value: portraitSignature, permissions: [.readable])
			let aggregateSignatureCharacteristic = CBMutableCharacteristic(type: CBUUID.AggregateSignatureCharacteristicID, properties: [.read], value: aggregateSignature, permissions: [.readable])
			let nicknameSignatureCharacteristic = CBMutableCharacteristic(type: CBUUID.NicknameSignatureCharacteristicID, properties: [.read], value: nicknameSignature, permissions: [.readable])
			let biographySignatureCharacteristic = CBMutableCharacteristic(type: CBUUID.BiographySignatureCharacteristicID, properties: [.read], value: biographySignature, permissions: [.readable])

			let peereeService = CBMutableService(type: CBUUID.PeereeServiceID, primary: true)
			peereeService.characteristics = [localPeerIDCharacteristic, remoteUUIDCharacteristic, pinnedCharacteristic, portraitCharacteristic, aggregateCharacteristic, lastChangedCharacteristic, nicknameCharacteristic, publicKeyCharacteristic, authCharacteristic, remoteAuthCharacteristic, peerIDSignatureCharacteristic, portraitSignatureCharacteristic, aggregateSignatureCharacteristic, nicknameSignatureCharacteristic, messageCharacteristic, biographyCharacteristic, biographySignatureCharacteristic]
			peripheral.add(peereeService)
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
		
		NSLog("ERROR: Failed to start advertising. (\(theError.localizedDescription))")
		stopAdvertising()
	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
		NSLog("Central read size: \(central.maximumUpdateValueLength)")
		switch characteristic.uuid {
		case CBUUID.BiographyCharacteristicID:
			send(data: UserPeerManager.instance.peer.biographyData, via: peripheral, of: characteristic as! CBMutableCharacteristic, to: central, sendSize: true)
		case CBUUID.PortraitCharacteristicID:
			do {
				let data = try Data(contentsOf: UserPeerManager.pictureResourceURL)
				send(data: data, via: peripheral, of: characteristic as! CBMutableCharacteristic, to: central, sendSize: true)
			} catch {
				NSLog("ERROR: Failed to read user portrait: \(error.localizedDescription)")
				NSLog("Removing picture from user info.")
				UserPeerManager.instance.cgPicture = nil
			}
		default:
			break
		}
	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
		interruptedTransfers = interruptedTransfers.filter { (_, _, interruptedCentral, _) -> Bool in // PERFORMANCE
			return interruptedCentral.identifier != central.identifier
		}
	}
	
	func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
		// Start sending again
		let transfers = interruptedTransfers
		interruptedTransfers.removeAll() // this keeps the elements in transfers
		for (data, characteristic, central, sendSize) in transfers {
			send(data: data, via: peripheral, of: characteristic, to: central, sendSize: sendSize)
		}
	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
		let centralID = request.central.identifier
		NSLog("Did receive read on \(request.characteristic.uuid.uuidString.left(8)) from central \(centralID)")
		if let data = UserPeerManager.instance.peer.getCharacteristicValue(of: request.characteristic.uuid) {
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
				let signature = try UserPeerManager.instance.keyPair.sign(message: nonce)
				
				if (request.offset > signature.count) {
					peripheral.respond(to: request, withResult: .invalidOffset)
				} else {
					request.value = signature.subdata(in: request.offset ..< signature.count-request.offset)
					peripheral.respond(to: request, withResult: .success)
				}
			} catch {
				NSLog("ERROR: Signing Bluetooth nonce failed: \(error)")
				peripheral.respond(to: request, withResult: .requestNotSupported)
			}
		} else if request.characteristic.uuid == CBUUID.RemoteAuthenticationCharacteristicID {
			guard let peerID = _availableCentrals[request.central.identifier] else {
				peripheral.respond(to: request, withResult: .insufficientResources)
				return
			}
			let randomByteCount = min(request.central.maximumUpdateValueLength, UserPeerManager.instance.keyPair.blockSize)
			var nonce = Data(count: randomByteCount)
			let status = nonce.withUnsafeMutablePointer({ SecRandomCopyBytes(kSecRandomDefault, randomByteCount, $0) })
			if status == errSecSuccess {
				remoteNonces[peerID] = nonce
				request.value = nonce
				peripheral.respond(to: request, withResult: .success)
			} else {
				NSLog("ERROR: Generating random Bluetooth nonce failed.")
				peripheral.respond(to: request, withResult: .unlikelyError)
			}
		} else {
			NSLog("WARN: Received unimplemented read request for characteristic: \(request.characteristic.uuid.uuidString)")
			peripheral.respond(to: request, withResult: .requestNotSupported)
		}
	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
		var error: CBATTError.Code = .success
		
		// these are the possible contents of the request
		var _peer: (PeerID, UUID)? = nil
		var _pin: (PeerID, Bool)? = nil
		var _nonce: (CBCentral, Data)? = nil
		var _message: (PeerID, String)? = nil
		
		for request in requests {
			NSLog("Did receive write on \(request.characteristic.uuid.uuidString.left(8)) from central \(request.central.identifier)")
			guard let data = request.value else {
				// this probably never happens
				NSLog("ERROR: received empty write request.")
				error = .unlikelyError
				break
			}
			if request.characteristic.uuid == CBUUID.MessageCharacteristicID {
				guard let message = String(dataPrefixedEncoding: data) else {
					error = .insufficientResources
					break
				}
				var peerID: PeerID
				if let _peerID = authenticatedPinMatchedCentrals[request.central.identifier] {
					peerID = _peerID
				} else if let _peerID = _availableCentrals[request.central.identifier] {
					// we allow fall back to accept messages from unauthenticated centrals here, since they aren't displayed in the UI anyway
					// and I got this behavior way too often that messages were sent before the mututal authentication took place
					peerID = _peerID
				} else {
					error = .insufficientResources
					break
				}
				_message = (peerID, message)
			} else if request.characteristic.uuid == CBUUID.RemoteUUIDCharacteristicID {
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
				
				let publicKeyData = AccountController.shared.publicKey(of: peerID)

				let signature = data

				// it is important that we use the same error code in both the "not a pin match" and "signature verification failed" cases, to prevent from the timing attack
				// we should not use CBATTError.insufficientAuthentication as then the iPhone begins a pairing process
				let authFailedError = CBATTError.insufficientAuthorization

				// we need to compute the verification in all cases, because if we would only do it if we have a public key available, it takes less time to fail if we did not pin the attacker -> timing attack: the attacker can deduce whether we pinned him, because he sees how much time it takes to fulfill their request
				do {
					// we use our public key as fake key, since we assume that our private key is not in the hands of the attacker (really!)
					let publicKey = try publicKeyData.map { try AsymmetricPublicKey(from: $0, type: PeerInfo.KeyType, size: PeerInfo.KeySize) } ?? UserPeerManager.instance.keyPair.publicKey
					try publicKey.verify(message: nonce, signature: signature)
					// we need to check if we pin MATCHED the peer, because if we would sent him a successful authentication return code while he did not already pin us, it means he can see that we pinned him
					if !AccountController.shared.hasPinMatch(peerID) {
						error = authFailedError // not a pin match
						NSLog("WARN: the peer \(peerID) which did not pin match us tried to authenticate to us.")
						break
					}
					authenticatedPinMatchedCentrals[request.central.identifier] = peerID
				} catch let exc {
					NSLog("ERROR: A peer tried to authenticate to us as \(peerID). Message: \(exc.localizedDescription)")
					error = authFailedError // signature verification failed
					break
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
				delegate?.localPeerDelegate(for: peerID).receivedPinMatchIndication()
			}
			if let (central, nonce) = _nonce {
				nonces[central.identifier] = nonce
			}
			if let (peerID, message) = _message {
				// attack scenario: Eve sends us a message with Bob's PeerID => we do not validate the PeerID and thus she can fake messages from other peers
				delegate?.localPeerDelegate(for: peerID).received(message: message)
			}
		}
		peripheral.respond(to: requests.first!, withResult: error)
	}
	
	// MARK: Private Methods
	
	private func send(data: Data, via peripheral: CBPeripheralManager, of characteristic: CBMutableCharacteristic, to central: CBCentral, sendSize: Bool) {
		if sendSize {
			// send the amount of bytes in data in the first package
			var size = CBCharacteristic.SplitCharacteristicSize(data.count)
			
			let sizeData = Data(bytesNoCopy: &size, count: MemoryLayout<CBCharacteristic.SplitCharacteristicSize>.size, deallocator: Data.Deallocator.none)
			guard peripheral.updateValue(sizeData, for: characteristic, onSubscribedCentrals: [central]) else {
				if isAdvertising {
					interruptedTransfers.append((data, characteristic, central, true))
				}
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
				if isAdvertising {
					interruptedTransfers.append((data.subdata(in: fromIndex..<data.endIndex), characteristic, central, false))
				}
				return
			}
			
			// It did send, so update our indices
			fromIndex = toIndex
			toIndex = data.index(fromIndex, offsetBy: central.maximumUpdateValueLength, limitedBy: data.endIndex) ?? data.endIndex
			
			// Was it the last one?
			send = fromIndex != data.endIndex
		}
		
		if fromIndex == data.endIndex {
			characteristic.value = nil
		}
	}
}
