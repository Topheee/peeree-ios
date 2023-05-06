//
//  RemotePeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.10.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import CoreGraphics
import CoreBluetooth
import KeychainWrapper
import PeereeCore

/// The informed party of a ``RemotePeerManager``, which handles the 'client' part of the Bluetooth communication
///
/// > Note: All methods are called from the manager's internal dispatch queue.
protocol RemotePeerManagerDelegate: AnyObject {
	/// Bluetooth network state change indicator.
	///
	/// - Parameter isReady: If `true`, Bluetooth is up and we have permission to access it, otherwise `false`.
	/// You may call ``RemotePeerManager/scan()``, if `isReady`.
	func remotePeerManager(isReady: Bool)

	/// The scan process stopped.
	///
	/// Either ``RemotePeerManager/stopScan()`` was called directly, or Bluetooth was turned of, or permissions where revoked.
	func scanningStopped()

	/// A new person was encountered.
	///
	/// - Parameter again: `true` if the peer was already in cache.
	func peerAppeared(_ peer: Peer, again: Bool)

	/// Bluetooth connection was disconnected.
	func peerDisappeared(_ peerID: PeerID, cbPeerID: UUID)

	/// Retrieved the biography of a person.
	func loaded(biography: String, of peer: Peer)

	/// Retrieved the picture of a person.
	func loaded(picture: CGImage, of peer: Peer, hash: Data)

	/// Estimated the signal strength to a person.
	func didRange(_ peerID: PeerID, rssi: NSNumber?, error: Error?)

	/// The verification process of the peer's public key failed.
	func failedVerification(of peerID: PeerID, error: Error)

	/// The person was able to proof that they are in possession of the private key belonging to their public key.
	func didVerify(_ peerID: PeerID)

	/// We identified ourselves to a person.
	func didRemoteVerify(_ peerID: PeerID)
}

/// The RemotePeerManager serves retrieves information from remote peers.
final class RemotePeerManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
	private struct PeerInfoData {
		var progress = Progress(totalUnitCount: 7)
		var aggregateData: Data? = nil
		var nicknameData: Data? = nil
		var peerIDSignatureData: Data? = nil
		var aggregateSignatureData: Data? = nil
		var nicknameSignatureData: Data? = nil
		var publicKeyData: Data? = nil
		var lastChangedData: Data? = nil
		var canConstruct: Bool {
			return aggregateData != nil && nicknameData != nil && publicKeyData != nil && peerIDSignatureData != nil && aggregateSignatureData != nil && nicknameSignatureData != nil
		}

		/// Saves the binary data of a ``Peer`` property and updates the receive progress.
		mutating func set(data: Data, for characteristicID: CBUUID) {
			switch characteristicID {
			case CBUUID.AggregateCharacteristicID:
				aggregateData = data
			case CBUUID.NicknameCharacteristicID:
				nicknameData = data
			case CBUUID.LastChangedCharacteristicID:
				lastChangedData = data
			case CBUUID.PublicKeyCharacteristicID:
				publicKeyData = data
			case CBUUID.PeerIDSignatureCharacteristicID:
				peerIDSignatureData = data
			case CBUUID.AggregateSignatureCharacteristicID:
				aggregateSignatureData = data
			case CBUUID.NicknameSignatureCharacteristicID:
				nicknameSignatureData = data
			default:
				elog("trying to set data for unknown characteristic \(characteristicID). Add it to PeerInfoData.set().")
				return
			}

			var count = Int64(0)
			for datum in [aggregateData, nicknameData, publicKeyData, peerIDSignatureData, aggregateSignatureData, nicknameSignatureData] {
				if datum != nil {
					count += Int64(1)
				}
			}
			progress.completedUnitCount = count
		}

		/// Constructs a ``Peer`` from binary data after verifying its authenticity.
		///
		/// - Returns: The ``Peer`` representing the received binary data, or `nil` if the binary data is still incomplete.
		///
		/// - Throws: A low-level Cocoa `CFError` if the signatures do not match.
		func makePeer(with peerID: PeerID) throws -> Peer? {
			guard let pubKeyData = publicKeyData,
				  let aggData = aggregateData,
				  let nickData = nicknameData,
				  let idSigData = peerIDSignatureData,
				  let aggSigData = aggregateSignatureData,
				  let nickSigData = nicknameSignatureData,
				  var peer = Peer(peerID: peerID, publicKeyData: pubKeyData, aggregateData: aggData, nicknameData: nickData) else { return nil }

			if let data = lastChangedData { peer.info.lastChangedData = data }

			do {
				for (data, signature) in [(peer.id.idData, idSigData), (aggData, aggSigData), (nickData, nickSigData)] {
					try peer.id.publicKey.verify(message: data, signature: signature)
				}
			} catch {
				progress.cancel()
				throw error
			}

			// make sure that the progress is marked as completed
			progress.completedUnitCount = progress.totalUnitCount
			return peer
		}
	}

	public enum ReliableWriteError: Error {
		case lostConnection, unknownPeripheralOrCharacteristic, valueTooLong, reliableWriteAlreadyInProgress, bleError(Error)
	}

	private let dQueue = DispatchQueue(label: "com.peeree.remotepeermanager_q", qos: .default, attributes: [])

	/// Our peerID; access only from `dQueue`.
	private var userPeerID: PeerID? = nil

	/// For authenticating ourselves.
	private var keyPair: KeyPair? = nil

	/// Needed for writing nonces; `16` is a good estimation.
	private var blockSize = 16

	/// Since bluetooth connections are not very durable, all peers and their images are cached.
	private var cachedPeers = [PeerID : Peer]()
	private var peerInfoTransmissions = [PeerID : PeerInfoData]()

	private var activeTransmissions = [Transmission : (Progress, Data)]()
	private var reliableWriteProcesses = [Transmission : (DispatchQueue, (ReliableWriteError?) -> Void)]()
	
	private var centralManager: CBCentralManager!
	
	/// All readable remote peers the app is currently connected to. The keys are updated immediately when a new peripheral shows up, as we have to keep a reference to it. However, the values are not filled until the peripheral tell's us his ID.
	private var _availablePeripherals = [CBPeripheral : PeerID?]()

	/// Maps the identifiers of peripherals to the IDs of the peers they represent.
	private var peripheralPeerIDs = SynchronizedDictionary<PeerID, CBPeripheral>(queueLabel: "\(BundleID).peripheralPeerIDs")

	/// Random bytes used for cryptographic signing and verification.
	private var nonces = [CBPeripheral : Data]()
	private var portraitSignatures = [PeerID : Data]()
	private var biographySignatures = [PeerID : Data]()

	weak var delegate: RemotePeerManagerDelegate?
	
	var availablePeers: [PeerID] {
		return peripheralPeerIDs.accessSync { (dictionary) in
			return dictionary.compactMap { (peerID, peripheral) -> PeerID? in
				(peripheral.services?.isEmpty ?? true) || peripheral.state != .connected ? nil : peerID
			}
		}
	}

	/// Whether the underlying `CBCentralManager` is scanning for peripherals; must be called on `dQueue`.
	private var isScanning: Bool {
		if #available(macOS 10.13, iOS 6.0, *) {
			return centralManager.isScanning
		} else {
			return true // shitty shit is not available on mac - what the fuck?
		}
	}

	/// Whether the underlying `CBCentralManager` is scanning for peripherals.
	func checkIsScanning(_ callback: @escaping (Bool) -> Void) {
		dQueue.async { callback(self.isScanning) }
	}
	
	func scan() {
		// we need to allow duplicates, because in the following scenario non-allow did not work:
		// 0. both are online and found each other
		// 1. the other peer goes offline and back online
		// 2. he finds me, but I do not find him, because my CentralManager does not report him, because we disconnected him
		//centralManager.scanForPeripherals(withServices: [CBUUID.PeereeServiceID], options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
		dQueue.async {
#if os(iOS)
			guard !self.isScanning else { return }
#endif

			self.centralManager.scanForPeripherals(withServices: [CBUUID.PeereeServiceID])
		}
	}
	
	func stopScan() {
		dQueue.async {
			guard self.isScanning else { return }

			self.centralManager.stopScan()
			for (_, (progress, _)) in self.activeTransmissions {
				progress.cancel()
			}
			self.activeTransmissions.removeAll()
			self.reliableWriteProcesses.removeAll()
			self.peerInfoTransmissions.removeAll()
			for (peripheral, _) in self._availablePeripherals {
				self.disconnect(peripheral)
			}
			// we may NOT empty this here, as this deallocates the CBPeripheral and thus didDisconnect is never invoked (and the central manager does not even recognize that we disconnected internally)!
//			self._availablePeripherals.removeAll()
			self.nonces.removeAll()
			self.peripheralPeerIDs.removeAll()
			self.cachedPeers.removeAll()
			self.delegate?.scanningStopped()
		}
	}

	/// Defines the values of our Peeree Identity.
	func set(userPeerID peerID: PeerID?, keyPair: KeyPair?) {
		dQueue.async {
			self.userPeerID = peerID
			self.keyPair = keyPair
			self.blockSize = keyPair?.blockSize ?? self.blockSize
		}
	}

	/// Reads `signatureCharacteristicID` and subscribes to `characteristicID`.
	func loadResource(of peerID: PeerID, characteristicID: CBUUID, signatureCharacteristicID: CBUUID, callback: @escaping (Progress?) -> ()) {
		guard let peripheral = peripheralPeerIDs[peerID],
			let signatureCharacteristic = peripheral.peereeService?.get(characteristic: signatureCharacteristicID) else {
			callback(nil)
			return
		}

		peripheral.readValue(for: signatureCharacteristic)
		load(characteristicID: characteristicID, of: peripheral, callback: callback)
	}

	/// Retrieves the progress of a big characteristic without triggering the load.
	func loadProgress(for characteristicID: CBUUID, of peerID: PeerID, callback: @escaping (Progress?) -> ()) {
		guard let peripheral = peripheralPeerIDs[peerID] else {
			callback(nil)
			return
		}
		dQueue.async {
			callback(self.loadingProgress(for: characteristicID, of: peripheral))
		}
	}

	func isReliablyWriting(to characteristicID: CBUUID, of peerID: PeerID) -> Bool {
		guard let peripheral = peripheralPeerIDs[peerID] else { return false }
		return dQueue.sync {
			self.reliableWriteProcesses[Transmission(peripheralID: peripheral.identifier, characteristicID: characteristicID)] != nil
		}
	}
	
	func reliablyWrite(data: Data, to characteristicID: CBUUID, of peerID: PeerID, callbackQueue: DispatchQueue, completion: @escaping (ReliableWriteError?) -> Void) {
		dQueue.async {
			guard let peripheral = self.peripheralPeerIDs[peerID],
				let characteristic = peripheral.peereeService?.get(characteristic: characteristicID) else {
				callbackQueue.async { completion(.unknownPeripheralOrCharacteristic) }
				return
			}
			guard peripheral.maximumWriteValueLength(for: CBCharacteristicWriteType.withResponse) >= data.count else {
				callbackQueue.async { completion(.valueTooLong) }
				return
			}
			let transmission = Transmission(peripheralID: peripheral.identifier, characteristicID: characteristic.uuid)
			if self.reliableWriteProcesses[transmission] == nil {
				self.reliableWriteProcesses[transmission] = (callbackQueue, completion)
				peripheral.writeValue(data, for: characteristic, type: .withResponse)
			} else {
				callbackQueue.async { completion(.reliableWriteAlreadyInProgress) }
			}
		}
	}
	
	func range(_ peerID: PeerID) {
		peripheralPeerIDs[peerID]?.readRSSI()
	}
	
	func verify(_ peerID: PeerID) {
		guard let peripheral = peripheralPeerIDs[peerID], let characteristic = peripheral.peereeService?.get(characteristic: CBUUID.AuthenticationCharacteristicID) else {
			delegate?.failedVerification(of: peerID, error: NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Insufficient resources for writing Bluetooth nonce.", comment: "Error during peer verification")]))
			return
		}
		writeNonce(to: peripheral, with: peerID, characteristic: characteristic)
	}
	
	func authenticate(_ peerID: PeerID) {
		guard let peripheral = peripheralPeerIDs[peerID], let characteristic = peripheral.peereeService?.get(characteristic: CBUUID.RemoteAuthenticationCharacteristicID) else {
			elog("Insufficient resources for reading Bluetooth nonce.")
			return
		}
		peripheral.readValue(for: characteristic)
	}
	
	// MARK: CBCentralManagerDelegate
	
//	@available(iOS 9.0, *)
//	func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
//		#if os(iOS)
//		let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as! [CBPeripheral]
//		// both always the same
////		let scanOptions = dict[CBCentralManagerRestoredStateScanOptionsKey]
////		let scanServices = dict[CBCentralManagerRestoredStateScanServicesKey]
//
//		for peripheral in peripherals {
//			_availablePeripherals.updateValue(nil, forKey: peripheral)
//			peripheral.delegate = self
//		}
//		#endif
//	}
	
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		// needed for state restoration as we may not have a "clean" state here anymore
		switch central.state {
		case .unknown, .resetting:
			// just wait
			break
		case .unsupported, .unauthorized:
			stopScan()
		case .poweredOff:
			stopScan()
		case .poweredOn:
			for (peripheral, _) in _availablePeripherals {
				// have we discovered our service?
				guard let service = peripheral.peereeService else {
					peripheral.discoverServices([CBUUID.PeereeServiceID])
					continue
				}
				// have we discovered the characteristics?
				guard let characteristics = service.get(characteristics: [CBUUID.AuthenticationCharacteristicID, CBUUID.LocalPeerIDCharacteristicID, CBUUID.RemoteUUIDCharacteristicID]), characteristics.count == 3 else {
					peripheral.discoverCharacteristics(CBUUID.PeereeCharacteristicIDs, for:service)
					continue
				}
				
				peripheral.readValue(for: characteristics[1])
				userPeerID.map { peripheral.writeValue($0.encode(), for: characteristics[2], type: .withResponse) }
			}
		default:
			break
		}

		delegate?.remotePeerManager(isReady: central.state == .poweredOn)
	}
	
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		wlog("Failed to connect to \(peripheral) (\(error?.localizedDescription ?? "")).")
		disconnect(peripheral)
	}
	
	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//		ilog("Discovered peripheral \(peripheral) with advertisement data \(advertisementData).")
		
		if _availablePeripherals[peripheral] == nil {
			_availablePeripherals.updateValue(nil, forKey: peripheral)
		}
		if peripheral.state == .disconnected {
			central.connect(peripheral, options: nil)
		}
	}
	
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		dlog("Connected peripheral \(peripheral)")
		peripheral.delegate = self
		peripheral.discoverServices([CBUUID.PeereeServiceID])
	}
	
	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		dlog("Disconnected peripheral \(peripheral) \(error != nil ? error!.localizedDescription : "")")
		// error is set when the peripheral disconnected without us having called disconnectPeripheral before, so in almost all cases...
		for characteristicID in CBUUID.SplitCharacteristicIDs {
			cancelTransmission(to: peripheral, of: characteristicID)
		}
		reliableWriteProcesses = reliableWriteProcesses.filter { entry in
			let (queue, callback) = entry.value
			if entry.key.peripheralID == peripheral.identifier {
				queue.async { callback(.lostConnection) }
			}
			return entry.key.peripheralID != peripheral.identifier
		}
		_ = nonces.removeValue(forKey: peripheral)
		guard let _peerID = _availablePeripherals.removeValue(forKey: peripheral), let peerID = _peerID else { return }
		if let peerData = peerInfoTransmissions.removeValue(forKey: peerID) {
			peerData.progress.cancel()
		}
		_ = peripheralPeerIDs.removeValue(forKey: peerID)
		delegate?.peerDisappeared(peerID, cbPeerID: peripheral.identifier)
	}
	
	// MARK: CBPeripheralDelegate
	
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		guard error == nil else {
			elog("Error discovering services: \(error!.localizedDescription)")
			disconnect(peripheral)
			return
		}
		guard let services = peripheral.services, services.count > 0 else {
			wlog("Found peripheral with no services.")
			disconnect(peripheral)
			return
		}

		// Loop through the newly filled peripheral.services array, just in case there's more than one.
		for service in services {
			dlog("Discovered service \(service.uuid.uuidString).")
			guard service.uuid == CBUUID.PeereeServiceID else { continue }

			// Discover the characteristic we want...
			peripheral.discoverCharacteristics(CBUUID.PeereeCharacteristicIDs, for:service)
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		guard error == nil else {
			elog("discovering characteristics failed: \(error!.localizedDescription)")
			disconnect(peripheral)
			return
		}
		guard let characteristics = service.characteristics else {
			elog("discovering characteristics failed: characteristics array is nil.")
			disconnect(peripheral)
			return
		}

		var found = false
		let charUUIDs = characteristics.map { $0.uuid.uuidString.left(8) }
		dlog("Discovered characteristics \(charUUIDs.joined(separator: ", ")) of service \(service.uuid.uuidString.left(8)) on peripheral \(peripheral.identifier.uuidString.left(8))")
		for characteristic in characteristics {
			switch characteristic.uuid {
			case CBUUID.LocalPeerIDCharacteristicID:
				peripheral.readValue(for: characteristic)
				found = true
			case CBUUID.RemoteUUIDCharacteristicID:
				userPeerID.map { peripheral.writeValue($0.encode(), for: characteristic, type: .withResponse) }
			case CBUUID.ConnectBackCharacteristicID:
				peripheral.writeValue(true.binaryRepresentation, for: characteristic, type: .withResponse)
			default:
				break // characteristic will be used later
			}
		}
		
		if !found {
			elog("No UUID characteristic found on peripheral \(peripheral). Disconnecting.")
			disconnect(peripheral)
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		guard error == nil else {
			if let cbError = error as? CBError {
				elog("CBError \(cbError.code.rawValue) receiving characteristic \(characteristic.uuid.uuidString) update: \(cbError.localizedDescription)")
			} else if let cbAttError = error as? CBATTError {
				elog("CBATTError \(cbAttError.code.rawValue) receiving characteristic \(characteristic.uuid.uuidString) update: \(cbAttError.localizedDescription)")
			} else if let nsError = error as? NSError {
				elog("Error \(nsError.code), domain \(nsError.domain) receiving characteristic \(characteristic.uuid.uuidString) update: \(nsError.localizedDescription)")
			}

			cancelTransmission(to: peripheral, of: characteristic.uuid)
			if characteristic.uuid == CBUUID.AuthenticationCharacteristicID {
				guard let peerID = peerID(of: peripheral) else { return }
				delegate?.failedVerification(of: peerID, error: error!)
			}
			return
		}
		
		guard let chunk = characteristic.value else { return } // TODO we probably have to cancel the transmission here and set our local value to nil as well if this ever really happens
		let transmission = Transmission(peripheralID: peripheral.identifier, characteristicID: characteristic.uuid)
		
		guard let (progress, _) = activeTransmissions[transmission] else {
			// first chunk, udpated without request
			processFirstChunk(chunk, transmission: transmission, peripheral: peripheral, characteristic: characteristic)
			return
		}
		guard !progress.isCancelled else {
			if characteristic.isNotifying {
				peripheral.setNotifyValue(false, for: characteristic)
			}
			return
		}
		guard progress.totalUnitCount > 0 else {
			processFirstChunk(chunk, transmission: transmission, peripheral: peripheral, characteristic: characteristic)
			return
		}
		
		activeTransmissions[transmission]?.1.append(chunk)
		let data = activeTransmissions[transmission]!.1
		
		let transmissionCount = Int64(data.count)
		
		// Have we got everything we need?
		if transmissionCount == progress.totalUnitCount {
			defer {
				// Cancel our subscription to the characteristic, whether an error occured or not
				peripheral.setNotifyValue(false, for: characteristic)
				// and drop the transmission
				activeTransmissions.removeValue(forKey: transmission)

				// try to close the connection if we are not retrieving any other data from the peripheral
				disconnectConditionally(peripheral)
			}

			guard let peerID = peerID(of: peripheral), let peer = cachedPeers[peerID] else {
				elog("Loaded \(characteristic.uuid.uuidString) resource characteristic of unknown peripheral \(peripheral).")
				progress.cancel()
				return
			}
			switch characteristic.uuid {
			case CBUUID.PortraitCharacteristicID:
				guard let signature = portraitSignatures.removeValue(forKey: peerID) else {
					elog("No signature for loaded portrait provided")
					progress.cancel()
					return
				}
				
				do {
					try peer.id.publicKey.verify(message: data, signature: signature)
				} catch {
					elog("Verification for loaded portrait failed: \(error.localizedDescription)")
					progress.cancel()
					return
				}
				
				guard let image = CGImage(jpegDataProviderSource: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent) else {
					elog("Failed to create image with data \(data).")
					progress.cancel()
					return
				}
				delegate?.loaded(picture: image, of: peer, hash: data.sha256())
			case CBUUID.BiographyCharacteristicID:
				guard let signature = biographySignatures.removeValue(forKey: peerID) else {
					elog("No signature for loaded portrait provided.")
					progress.cancel()
					return
				}
				
				do {
					try peer.id.publicKey.verify(message: data, signature: signature)
				} catch {
					elog("Verification for loaded biography failed: \(error.localizedDescription)")
					progress.cancel()
					return
				}
				
				guard let biography = String(dataPrefixedEncoding: data) else {
					elog("Failed to create biography with data \(data).")
					progress.cancel()
					return
				}
				delegate?.loaded(biography: biography, of: peer)
			default:
				break
			}
		}
		
		progress.completedUnitCount = transmissionCount
	}
	
	private var malformedTimer: Timer?
	private func processFirstChunk(_ chunk: Data, transmission: Transmission, peripheral: CBPeripheral, characteristic: CBCharacteristic) {
		switch transmission.characteristicID {
		case CBUUID.LocalPeerIDCharacteristicID:
			guard let peerID = PeerID(data: chunk) else {
				elog("Retrieved malformed peer ID \(String(data: chunk, encoding: .utf8) ?? "<non-utf8 string>"). Disconnecting peer \(peripheral).")
				disconnect(peripheral)
				if #available(iOS 10.0, *) {
					// does not work yet
					malformedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false, block: { _ in
						self.malformedTimer = nil
						self.centralManager?.connect(peripheral, options: nil)
					})
				} else {
					// Not supported on earlier versions
				}
				return
			}

			// sometimes (especially with Android) it happens that a device connects again while having the old connection still open
			if let oldPeripheral = peripheralPeerIDs[peerID], oldPeripheral.state == .connected || oldPeripheral.state == .connecting {
				// we where already connected, so simply discard the old peripheral and silenty adopt the new one
				disconnect(oldPeripheral)
			}

			_availablePeripherals[peripheral] = peerID
			peripheralPeerIDs[peerID] = peripheral

			if let peer = cachedPeers[peerID] {
				// we discovered this one earlier but he went offline in between (modified services to nil or empty, resp.) but now he is back online again
				peerAppeared(peer, peripheral: peripheral, again: true)
				// always read last changed characteristic to get aware of LastChangedCharacteristicID
				guard let lastChangedCharacteristic = peripheral.peereeService?.get(characteristic: CBUUID.LastChangedCharacteristicID) else { break }
				peripheral.readValue(for: lastChangedCharacteristic)
			} else {
				guard let characteristics = peripheral.peereeService?.get(characteristics: [CBUUID.AggregateCharacteristicID, CBUUID.NicknameCharacteristicID, CBUUID.PeerIDSignatureCharacteristicID, CBUUID.AggregateSignatureCharacteristicID, CBUUID.NicknameSignatureCharacteristicID, CBUUID.PublicKeyCharacteristicID, CBUUID.LastChangedCharacteristicID]) else { break }
				peripheral.readValues(for: characteristics)
			}
			
		case CBUUID.AuthenticationCharacteristicID:
			let signature = chunk
			guard let nonce = nonces.removeValue(forKey: peripheral), let peerID = peerID(of: peripheral), let peer = cachedPeers[peerID] else {
				break
			}
			
			do {
				try peer.id.publicKey.verify(message: nonce, signature: signature)
				delegate?.didVerify(peerID)
			} catch {
				delegate?.failedVerification(of: peerID, error: error)
			}
			
		case CBUUID.RemoteAuthenticationCharacteristicID:
			keyPair.map {
				do {
					let signature = try $0.sign(message: chunk)

					peripheral.writeValue(signature, for: characteristic, type: .withResponse)
				} catch {
					// TODO present an alert to the user that they won't be able to send messages
					elog("Signing Bluetooth remote nonce failed: \(error)")
				}
			}

		case CBUUID.PortraitCharacteristicID, CBUUID.BiographyCharacteristicID:
			guard chunk.count >= MemoryLayout<Int32>.size else { break }

			var size: CBCharacteristic.SplitCharacteristicSize = 0
			withUnsafeMutableBytes(of: &size) { pointer in
				pointer.copyBytes(from: chunk.subdata(in: 0..<MemoryLayout<Int32>.size))
			}

			// make sure the picture / biography is not too big (13 MB)
			guard size < 13678905  && size > 0 else {
				elog("\(transmission.characteristicID.uuidString.left(8)) is too big or small: \(size) bytes.")
				return
			}

			if let (progress, _) = activeTransmissions[transmission] {
				progress.totalUnitCount = Int64(size)
			} else {
				let progress = Progress(totalUnitCount: Int64(size))
				activeTransmissions[transmission] = (progress, Data(capacity: Int(size)))
			}
			
		case CBUUID.PortraitSignatureCharacteristicID:
			peerID(of: peripheral).map { portraitSignatures[$0] = chunk }

		case CBUUID.BiographySignatureCharacteristicID:
			peerID(of: peripheral).map { biographySignatures[$0] = chunk }

		default:
			guard let peerID = peerID(of: peripheral) else { return }
			if cachedPeers[peerID] != nil {
				if transmission.characteristicID == CBUUID.LastChangedCharacteristicID {
					let knownState = cachedPeers[peerID]!.info.lastChanged
					cachedPeers[peerID]!.info.lastChangedData = chunk
					if cachedPeers[peerID]!.info.lastChanged > knownState {
						// the peer has a newer state then the one we cached, so reload all changeable properties
						guard let characteristics = peripheral.peereeService?.get(characteristics: [CBUUID.AggregateCharacteristicID, CBUUID.NicknameCharacteristicID, CBUUID.PeerIDSignatureCharacteristicID, CBUUID.AggregateSignatureCharacteristicID, CBUUID.NicknameSignatureCharacteristicID, CBUUID.LastChangedCharacteristicID]) else { break }
						peripheral.readValues(for: characteristics)
					} else {
						disconnectConditionally(peripheral)
					}
				} else {
//					fatalError()
					// TODO SECURITY characteristic is not verified
					// TODO this does not get published within the app so that the view does not update (make sure the value really changed)
//					cachedPeers[peerID]!.setCharacteristicValue(of: transmission.characteristicID, to: chunk)
				}
			} else {
				var peerData = peerInfoTransmissions[peerID] ?? PeerInfoData()
				peerData.set(data: chunk, for: transmission.characteristicID)

				do {
					if let peer = try peerData.makePeer(with: peerID) {
						peerInfoTransmissions.removeValue(forKey: peerID)
						cachedPeers[peerID] = peer
						peerAppeared(peer, peripheral: peripheral, again: false)
					} else {
						peerInfoTransmissions[peerID] = peerData
					}
				} catch {
					// one of the signatures does not match
					elog("Characteristic verification failed: \(error)")
					disconnect(peripheral)
				}
			}
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
		guard error == nil else {
			elog("Error changing notification state: \(error!.localizedDescription)")
			if !characteristic.isNotifying {
				cancelTransmission(to: peripheral, of: characteristic.uuid)
			}
			return
		}

		dlog("Notification \(characteristic.isNotifying ? "began" : "stopped" ) on \(characteristic.uuid.uuidString).")
	}
	
	#if os(iOS)
	func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
		dlog("Did read RSSI \(RSSI) of peripheral \(peripheral).")
		guard let peerID = peerID(of: peripheral) else { assertionFailure(); return }
		delegate?.didRange(peerID, rssi: RSSI, error: error)
	}
	#else
	func peripheralDidUpdateRSSI(_ peripheral: CBPeripheral, error: Error?) {
		guard let peerID = peerID(of: peripheral) else { assertionFailure(); return }
		delegate?.didRange(peerID, rssi: peripheral.rssi, error: error)
	}
	#endif
	
	func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
		dlog("Peripheral transitioned from services \(invalidatedServices) to \(String(describing: peripheral.services)).")
		if invalidatedServices.count > 0 && (peripheral.services == nil || peripheral.services!.isEmpty) {
			if peripheral.state == .connected {
				disconnect(peripheral)
			}
			// we cannot disconnect like above as then, if the other peer goes online again, we won't get informed of that
			// so we just pretend it went offline
			// but in this case we would have to check for services on actual disconnect!!!!
//			guard let peerID = peerID(of: peripheral) else { return }
//			delegate?.peerDisappeared(peerID)
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
		if let (callbackQueue, completion) = reliableWriteProcesses.removeValue(forKey: Transmission(peripheralID: peripheral.identifier, characteristicID: characteristic.uuid)) {
			let completionError: ReliableWriteError?
			if let error = error {
				completionError = ReliableWriteError.bleError(error)
			} else {
				completionError = nil
			}
			callbackQueue.async { completion(completionError) }
		}
		guard error == nil else {
			elog("Error writing \(characteristic.uuid.uuidString.left(8)) to PeerID \(peerID(of: peripheral)?.uuidString.left(8) ?? "unknown"): \(error!.localizedDescription).")
			return
		}
		guard let peerID = peerID(of: peripheral) else { return }
		if characteristic.uuid == CBUUID.AuthenticationCharacteristicID {
			guard cachedPeers[peerID] != nil else { return }
			// if we loaded the peer info, we can store the verification state
			// if it is not loaded, reading the signed nonce is initiated on load
			peripheral.readValue(for: characteristic)
		} else if characteristic.uuid == CBUUID.RemoteAuthenticationCharacteristicID {
			delegate?.didRemoteVerify(peerID)
		}
	}
	
	func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
		dlog("Peripheral \(peripheral) did update name")
	}
	
	override init() {
		centralManager = nil
		super.init()
//		#if os(iOS)
//		centralManager = CBCentralManager(delegate: self, queue: dQueue, options: [CBCentralManagerOptionShowPowerAlertKey : 1, CBCentralManagerOptionRestoreIdentifierKey : "CentralManager"])
//		#else
		centralManager = CBCentralManager(delegate: self, queue: dQueue, options: [CBCentralManagerOptionShowPowerAlertKey : 1])
//		#endif
	}
	
	// MARK: Private Methods

	/// Begin verification process and notify delegate.
	private func peerAppeared(_ peer: Peer, peripheral: CBPeripheral, again: Bool) {
		verify(peer.id.peerID)
		delegate?.peerAppeared(peer, again: again)
	}

	/// If no active communication is happening with `peripheral`, disconnect from it.
	private func disconnectConditionally(_ peripheral: CBPeripheral) {
		guard let _peerID = _availablePeripherals[peripheral], let peerID = _peerID else {
			disconnect(peripheral)
			return
		}

		dlog("peerInfoTransmissions[peerID] == nil: \(peerInfoTransmissions[peerID] == nil)")
		dlog("!(activeTransmissions.contains { $0.key.peripheralID == peripheral.identifier }): \(!(activeTransmissions.contains { $0.key.peripheralID == peripheral.identifier }))")
		dlog("!(reliableWriteProcesses.contains { $0.key.peripheralID == peripheral.identifier }): \(!(reliableWriteProcesses.contains { $0.key.peripheralID == peripheral.identifier }))")
		dlog("portraitSignatures[peerID] == nil: \(portraitSignatures[peerID] == nil)")
		dlog("biographySignatures[peerID] == nil: \(biographySignatures[peerID] == nil)")
		// be careful: if a new transmission or reliable-write characteristic is added, we need to add it here, too!
		guard peerInfoTransmissions[peerID] == nil &&
			!(activeTransmissions.contains { $0.key.peripheralID == peripheral.identifier }) &&
			!(reliableWriteProcesses.contains { $0.key.peripheralID == peripheral.identifier }) &&
			portraitSignatures[peerID] == nil &&
			biographySignatures[peerID] == nil else {
				return
			}

		// turned off since we seem to do it too early, s. t. either bio or picture aren't loaded: disconnect(peripheral)
	}

	/// Close the connection to `peripheral`.
	private func disconnect(_ peripheral: CBPeripheral) {
		// Don't do anything if we're not connected
		guard peripheral.state == .connected || peripheral.state == .connecting else { return }
		
		// See if we are subscribed to a characteristic on the peripheral
		if let services = peripheral.services {
			for service in services {
				guard service.characteristics != nil else { continue }
				for characteristic in service.characteristics! {
					if characteristic.isNotifying {
						peripheral.setNotifyValue(false, for: characteristic)
					}
				}
			}
		}
		
		centralManager.cancelPeripheralConnection(peripheral)
	}

	// characteristicID is ! because CBMutableCharacteristic.uuid is fucking optional on macOS
	private func load(characteristicID: CBUUID!, of peripheral: CBPeripheral, callback: @escaping (Progress?) -> ()) {
		dQueue.async {
			if let progress = self.loadingProgress(for: characteristicID, of: peripheral) {
				callback(progress)
				return
			}

			guard let characteristic = peripheral.peereeService?.get(characteristic: characteristicID) else {
				elog("Tried to load unknown characteristic \(characteristicID.uuidString).")
				callback(nil)
				return
			}

			let transmission = Transmission(peripheralID: peripheral.identifier, characteristicID: characteristic.uuid)
			let progress = Progress(parent: nil, userInfo: nil)
			self.activeTransmissions[transmission] = (progress, Data())
			peripheral.setNotifyValue(true, for: characteristic)
			callback(progress)
		}
	}

	/// Retrieves the loading progress for `characteristicID`; call only from `dQueue`!
	private func loadingProgress(for characteristicID: CBUUID, of peripheral: CBPeripheral) -> Progress? {
		return activeTransmissions[Transmission(peripheralID: peripheral.identifier, characteristicID: characteristicID)]?.0
	}

	/// Removes the transmission from the internal cache and cancels its progress, if available.
	private func cancelTransmission(to peripheral: CBPeripheral, of characteristicID: CBUUID) {
		let transmission = Transmission(peripheralID: peripheral.identifier, characteristicID: characteristicID)
		guard let (progress, _) = activeTransmissions.removeValue(forKey: transmission) else { return }
		
		progress.cancel()
	}
	
	private func peerID(of peripheral: CBPeripheral) -> PeerID? {
		guard let _peerID = _availablePeripherals[peripheral] else { return nil }
		return _peerID
	}
	
	private func writeNonce(to peripheral: CBPeripheral, with peerID: PeerID, characteristic: CBCharacteristic) {
		let writeType = CBCharacteristicWriteType.withResponse
		let randomByteCount = min(peripheral.maximumWriteValueLength(for: writeType), blockSize)
		do {
			var nonce = try generateRandomData(length: randomByteCount)
			nonces[peripheral] = nonce
			peripheral.writeValue(nonce, for: characteristic, type: writeType)
			nonce.resetBytes(in: 0..<nonce.count)
		} catch let error {
			delegate?.failedVerification(of: peerID, error: error)
		}
	}
}

struct Transmission {
	let peripheralID: UUID
	let characteristicID: CBUUID
}

/// Compiler generates hash(into: for us)
extension Transmission: Hashable {
	static func ==(lhs: Transmission, rhs: Transmission) -> Bool {
		return lhs.peripheralID == rhs.peripheralID && lhs.characteristicID == rhs.characteristicID
	}
}

extension PeerInfo {
	/// Parses binary data `to` and sets property according to `characteristicID` to the decoded value.
	mutating func setCharacteristicValue(of characteristicID: CBUUID, to: Data) {
		switch characteristicID {
		case CBUUID.AggregateCharacteristicID:
			aggregateData = to
		case CBUUID.LastChangedCharacteristicID:
			lastChangedData = to
		case CBUUID.NicknameCharacteristicID:
			nicknameData = to
		default:
			break
		}
	}
}
