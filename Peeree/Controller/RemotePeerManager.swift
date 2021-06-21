//
//  RemotePeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.10.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import CoreGraphics
import CoreBluetooth

protocol RemotePeerManagerDelegate: AnyObject {
	func remotePeerManagerIsReady()
	func peerAppeared(_ peerID: PeerID, again: Bool) -> RemotePeerDelegate
	func peerDisappeared(_ peerID: PeerID, cbPeerID: UUID)
}

protocol RemotePeerDelegate {
	func loaded(biography: String, of peerID: PeerID)
	func loaded(picture: CGImage, of peerID: PeerID, hash: Data)
	func didRange(_ peerID: PeerID, rssi: NSNumber?, error: Error?)
	func failedVerification(of peerID: PeerID, error: Error)
	func didVerify(_ peerID: PeerID)
	func didRemoteVerify(_ peerID: PeerID)
}

/// The RemotePeerManager singleton serves as an globally access point for information about all remote peers, whether they are currently in network range or were pinned in the past.
final class RemotePeerManager: NSObject, RemotePeering, CBCentralManagerDelegate, CBPeripheralDelegate {
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
				break
			}
			var count = Int64(0)
			for datum in [aggregateData, nicknameData, publicKeyData, peerIDSignatureData, aggregateSignatureData, nicknameSignatureData] {
				if datum != nil {
					count += Int64(1)
				}
			}
			progress.completedUnitCount = count
		}
		
		func construct(with peerID: PeerID) -> PeerInfo? {
			guard canConstruct else { return nil }
			
			guard var peer = PeerInfo(peerID: peerID, publicKeyData: publicKeyData!, aggregateData: aggregateData!, nicknameData: nicknameData!) else { return nil }
			if let data = lastChangedData { peer.lastChangedData = data }
			
			do {
				for (data, signature) in [(peer.idData, peerIDSignatureData), (aggregateData, aggregateSignatureData), (nicknameData, nicknameSignatureData)] {
					try peer.publicKey.verify(message: data!, signature: signature!)
				}
			} catch {
				// TODO populate error and inform user about possible malicious peer
				NSLog("Characteristic verification failed: \(error)")
				progress.cancel()
				return nil
			}
			
			progress.completedUnitCount = progress.totalUnitCount
			return peer
		}
	}

	public enum ReliableWriteError: Error {
		case lostConnection, unknownPeripheralOrCharacteristic, valueTooLong, reliableWriteAlreadyInProgress, bleError(Error)
	}

	private let dQueue = DispatchQueue(label: "com.peeree.remotepeermanager_q", attributes: [])
	
	///	Since bluetooth connections are not very durable, all peers and their images are cached.
	private var cachedPeers = SynchronizedDictionary<PeerID, PeerInfo>(queueLabel: "\(BundleID).cachedPeers")
	private var peerInfoTransmissions = [PeerID : PeerInfoData]()
	private var remotePeerDelegates = [PeerID : RemotePeerDelegate]()
	
	private var activeTransmissions = [Transmission : (Progress, Data)]() // TODO if the synchronization through the dQueue is too slow, switch to a delegate model, where the delegate is being told when a transmission begins/ends. Also, inform new delegates (via didSet and then dQueue.aysnc) of ongoing transmissions by calling transmissionDidBegin for every current transmission.
	private var reliableWriteProcesses = [Transmission : (DispatchQueue, (ReliableWriteError?) -> Void)]()
	
	private var centralManager: CBCentralManager!
	
	///	All readable remote peers the app is currently connected to. The keys are updated immediately when a new peripheral shows up, as we have to keep a reference to it. However, the values are not filled until the peripheral tell's us his ID.
	private var _availablePeripherals = [CBPeripheral : PeerID?]()
	/// Maps the identifieres of peripherals to the IDs of the peers they represent.
	private var peripheralPeerIDs = SynchronizedDictionary<PeerID, CBPeripheral>(queueLabel: "\(BundleID).peripheralPeerIDs")
	
	private var nonces = [CBPeripheral : Data]()
	private var portraitSignatures = [PeerID : Data?]()
	private var biographySignatures = [PeerID : Data?]()
	
	weak var delegate: RemotePeerManagerDelegate?
	
	var availablePeers: [PeerID] {
		return peripheralPeerIDs.accessSync { (dictionary) in
			return dictionary.compactMap { (peerID, peripheral) -> PeerID? in
				if peripheral.state != .connected || peripheral.services == nil || peripheral.services!.isEmpty {
					return nil
				} else {
					return peerID
				}
			}
		}
	}
	
	var isBluetoothOn: Bool { return centralManager.state == .poweredOn }
	
	var isScanning: Bool {
		if #available(macOS 10.13, iOS 6.0, *) {
			return centralManager.isScanning
		} else {
			return true // shitty shit is not available on mac - what the fuck?
		}
	}
	
	func scan() {
		#if os(iOS)
			guard !isScanning else { return }
		#endif
		
		// we need to allow duplicates, because in the following scenario non-allow did not work:
		// 0. both are online and found each other
		// 1. the other peer goes offline and back online
		// 2. he finds me, but I do not find him, because my CentralManager does not report him, because we disconnected him
		centralManager.scanForPeripherals(withServices: [CBUUID.PeereeServiceID], options: [CBCentralManagerScanOptionAllowDuplicatesKey:true])
	}
	
	func stopScan() {
		guard isScanning else { return }
		
		dQueue.sync {
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
		}
	}
	
	// characteristicID is ! because CBMutableCharacteristic.uuid is fucking optional on macOS
	private func load(characteristicID: CBUUID!, of peerID: PeerID) -> Progress? {
		guard isScanning, let peripheral = peripheralPeerIDs[peerID] else { return nil }
		
		return dQueue.sync {
			if let progress = isLoading(characteristicID: characteristicID, of: peripheral) {
				return progress
			} else {
				guard let characteristic = peripheral.peereeService?.get(characteristic: characteristicID) else {
					NSLog("Tried to load unknown characteristic \(characteristicID.uuidString).")
					return nil
				}
				let transmission = Transmission(peripheralID: peripheral.identifier, characteristicID: characteristic.uuid)
				let progress = Progress(parent: nil, userInfo: nil)
				self.activeTransmissions[transmission] = (progress, Data())
				peripheral.setNotifyValue(true, for: characteristic)
				return progress
			}
		}
	}
	
	private func isLoading(characteristicID: CBUUID, of peripheral: CBPeripheral) -> Progress? {
		// do not sync activeTransmissions with dQueue as we don't need to be 100% correct here
		return activeTransmissions[Transmission(peripheralID: peripheral.identifier, characteristicID: characteristicID)]?.0
	}
	
	func loadResource(of peerID: PeerID, characteristicID: CBUUID, signatureCharacteristicID: CBUUID) -> Progress? {
		guard let peripheral = peripheralPeerIDs[peerID],
			let signatureCharacteristic = peripheral.peereeService?.get(characteristic: signatureCharacteristicID) else { return nil }
		peripheral.readValue(for: signatureCharacteristic)
		return load(characteristicID: characteristicID, of: peerID)
	}
	
	func loadProgress(for characteristicID: CBUUID, of peerID: PeerID) -> Progress? {
		guard let peripheral = peripheralPeerIDs[peerID] else { return nil }
		return isLoading(characteristicID: characteristicID, of: peripheral)
	}
	
	func isPeerInfoLoading(of peerID: PeerID) -> Progress? {
		return peerInfoTransmissions[peerID]?.progress
	}
	
	func getPeerInfo(of peerID: PeerID) -> PeerInfo? {
		return cachedPeers[peerID]
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
			remotePeerDelegates[peerID]?.failedVerification(of: peerID, error: NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Insufficient resources for writing Bluetooth nonce.", comment: "Error during peer verification")]))
			return
		}
		writeNonce(to: peripheral, with: peerID, characteristic: characteristic)
	}
	
	func authenticate(_ peerID: PeerID) {
		guard let peripheral = peripheralPeerIDs[peerID], let characteristic = peripheral.peereeService?.get(characteristic: CBUUID.RemoteAuthenticationCharacteristicID) else {
			NSLog("ERROR: Insufficient resources for reading Bluetooth nonce.")
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
				peripheral.writeValue(UserPeerManager.instance.peer.idData, for: characteristics[2], type: .withResponse)
			}
			delegate?.remotePeerManagerIsReady()
		default:
			break
		}
	}
	
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		if error != nil {
			NSLog("Failed to connect to \(peripheral) (\(error!.localizedDescription)).")
		} else {
			NSLog("Failed to connect to \(peripheral).")
		}
		disconnect(peripheral)
	}
	
	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//		NSLog("INFO: Discovered peripheral \(peripheral) with advertisement data \(advertisementData).")
		
		if _availablePeripherals[peripheral] == nil {
			_availablePeripherals.updateValue(nil, forKey: peripheral)
		}
		if peripheral.state == .disconnected {
			central.connect(peripheral, options: nil)
		}
	}
	
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		NSLog("Connected peripheral \(peripheral)")
		peripheral.delegate = self
		peripheral.discoverServices([CBUUID.PeereeServiceID])
	}
	
	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		NSLog("Disconnected peripheral \(peripheral) \(error != nil ? error!.localizedDescription : "")")
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
			NSLog("Error discovering services: \(error!.localizedDescription)")
			disconnect(peripheral)
			return
		}
		guard peripheral.services != nil && peripheral.services!.count > 0 else {
			NSLog("Found peripheral with no services.")
			disconnect(peripheral)
			return
		}
		
		// Discover the characteristic we want...
		
		// Loop through the newly filled peripheral.services array, just in case there's more than one.
		for service in peripheral.services! {
			NSLog("Discovered service \(service.uuid.uuidString).")
			guard service.uuid == CBUUID.PeereeServiceID else { continue }
			
			peripheral.discoverCharacteristics(CBUUID.PeereeCharacteristicIDs, for:service)
//			peripheral.discoverCharacteristics(nil, for:service)
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		guard error == nil else {
			NSLog("ERROR: discovering characteristics failed: \(error!.localizedDescription)")
			disconnect(peripheral)
			return
		}
		guard let characteristics = service.characteristics else {
			NSLog("ERROR: discovering characteristics failed: characteristics array is nil.")
			disconnect(peripheral)
			return
		}

		var found = false
		let charUUIDs = characteristics.map { $0.uuid.uuidString.left(8) }
		NSLog("INFO: Discovered characteristics \(charUUIDs.joined(separator: ", ")) of service \(service.uuid.uuidString.left(8)) on peripheral \(peripheral.identifier.uuidString.left(8))")
		for characteristic in characteristics {
/*
			if let descriptors = characteristic.descriptors {
				for descriptor in descriptors {
					if let data = descriptor.value as? Data {
						if let s = String(data: data, encoding: String.Encoding.utf8) {
							NSLog("\t\(s)")
						} else if let s = String(data: data, encoding: String.Encoding.ascii) {
							NSLog("\t\(s)")
						} else {
							NSLog("\tunknown descriptor")
						}
					} else if let data = descriptor.value as? String {
						NSLog("\t\(data)")
					}
				}
			}
*/
			switch characteristic.uuid {
			case CBUUID.LocalPeerIDCharacteristicID:
				peripheral.readValue(for: characteristic)
				found = true
			case CBUUID.RemoteUUIDCharacteristicID:
				peripheral.writeValue(UserPeerManager.instance.peer.idData, for: characteristic, type: .withResponse)
			case CBUUID.ConnectBackCharacteristicID:
				peripheral.writeValue(true.binaryRepresentation, for: characteristic, type: .withResponse)
			default:
				break // characteristic will be used later
			}
		}
		
		if !found {
			NSLog("ERROR: No UUID characteristic found on peripheral \(peripheral). Disconnecting.")
			disconnect(peripheral)
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		guard error == nil else {
			if let cbError = error as? CBError {
				NSLog("CBError \(cbError.code.rawValue) receiving characteristic \(characteristic.uuid.uuidString) update: \(cbError.localizedDescription)")
			} else if let cbAttError = error as? CBATTError {
				NSLog("CBATTError \(cbAttError.code.rawValue) receiving characteristic \(characteristic.uuid.uuidString) update: \(cbAttError.localizedDescription)")
			} else {
				NSLog("Error \((error! as NSError).code), domain \((error! as NSError).domain) receiving characteristic \(characteristic.uuid.uuidString) update: \(error!.localizedDescription)")
			}
			cancelTransmission(to: peripheral, of: characteristic.uuid)
			if characteristic.uuid == CBUUID.AuthenticationCharacteristicID {
				guard let peerID = peerID(of: peripheral) else { return }
				remotePeerDelegates[peerID]?.failedVerification(of: peerID, error: error!)
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
			}

			guard let peerID = peerID(of: peripheral), let peer = cachedPeers[peerID] else {
				NSLog("Loaded \(characteristic.uuid.uuidString) resource characteristic of unknown peripheral \(peripheral).")
				progress.cancel()
				return
			}
			switch characteristic.uuid {
			case CBUUID.PortraitCharacteristicID:
				guard let _signature = portraitSignatures.removeValue(forKey: peerID), let signature = _signature else {
					NSLog("No signature for loaded portrait provided")
					progress.cancel()
					return
				}
				
				do {
					try peer.publicKey.verify(message: data, signature: signature)
				} catch {
					NSLog("Verification for loaded portrait failed: \(error.localizedDescription)")
					progress.cancel()
					return
				}
				
				guard let image = CGImage(jpegDataProviderSource: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent) else {
					NSLog("Failed to create image with data \(data).")
					progress.cancel()
					break
				}
				remotePeerDelegates[peerID]?.loaded(picture: image, of: peerID, hash: data.sha256())
			case CBUUID.BiographyCharacteristicID:
				guard let _signature = biographySignatures.removeValue(forKey: peerID), let signature = _signature else {
					NSLog("ERROR: No signature for loaded portrait provided.")
					progress.cancel()
					return
				}
				
				do {
					try peer.publicKey.verify(message: data, signature: signature)
				} catch {
					NSLog("ERROR: Verification for loaded biography failed: \(error.localizedDescription)")
					progress.cancel()
					return
				}
				
				guard let biography = String(dataPrefixedEncoding: data) else {
					NSLog("ERROR: Failed to create biography with data \(data).")
					progress.cancel()
					break
				}
				cachedPeers[peerID]?.biography = biography
				remotePeerDelegates[peerID]?.loaded(biography: biography, of: peerID)
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
				NSLog("ERROR: Retrieved malformed peer ID \(String(data: chunk, encoding: .utf8) ?? "<non-utf8 string>"). Disconnecting peer \(peripheral).")
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
			let _oldPeripheral = peripheralPeerIDs[peerID]
			_availablePeripherals[peripheral] = peerID
			peripheralPeerIDs[peerID] = peripheral

			if cachedPeers[peerID] == nil {
				guard let characteristics = peripheral.peereeService?.get(characteristics: [CBUUID.AggregateCharacteristicID, CBUUID.NicknameCharacteristicID, CBUUID.PeerIDSignatureCharacteristicID, CBUUID.AggregateSignatureCharacteristicID, CBUUID.NicknameSignatureCharacteristicID, CBUUID.PublicKeyCharacteristicID, CBUUID.LastChangedCharacteristicID]) else { break }
				peripheral.readValues(for: characteristics)
			} else if let oldPeripheral = _oldPeripheral, oldPeripheral.state == .connected || oldPeripheral.state == .connecting {
				// we where already connected, so simply discard the old peripheral and silenty adopt the new one
				disconnect(oldPeripheral)
			} else {
				// we discovered this one earlier but he went offline in between (modified services to nil or empty, resp.) but now he is back online again
				peerAppeared(peerID, peripheral: peripheral, again: true)
				// always read last changed characteristic to get aware of LastChangedCharacteristicID
				guard let lastChangedCharacteristic = peripheral.peereeService?.get(characteristic: CBUUID.LastChangedCharacteristicID) else { break }
				peripheral.readValue(for: lastChangedCharacteristic)
			}
			
		case CBUUID.AuthenticationCharacteristicID:
			let signature = chunk
			guard let nonce = nonces.removeValue(forKey: peripheral), let peerID = peerID(of: peripheral), let peer = getPeerInfo(of: peerID) else {
				break
			}
			
			do {
				try peer.publicKey.verify(message: nonce, signature: signature)
				remotePeerDelegates[peerID]?.didVerify(peerID)
			} catch {
				remotePeerDelegates[peerID]?.failedVerification(of: peerID, error: error)
			}
			
		case CBUUID.RemoteAuthenticationCharacteristicID:
			let nonce = chunk
			do {
				let signature = try UserPeerManager.instance.keyPair.sign(message: nonce)
				
				peripheral.writeValue(signature, for: characteristic, type: .withResponse)
			} catch {
				// TODO present an alert to the user that they won't be able to send messages
				NSLog("ERROR: Signing Bluetooth remote nonce failed: \(error)")
			}
			
		case CBUUID.PortraitCharacteristicID, CBUUID.BiographyCharacteristicID:
			var size: CBCharacteristic.SplitCharacteristicSize = 0
			withUnsafeMutableBytes(of: &size) { pointer in
				pointer.copyBytes(from: chunk)
			}
			if let (progress, _) = activeTransmissions[transmission] {
				progress.totalUnitCount = Int64(size)
			} else {
				let progress = Progress(totalUnitCount: Int64(size))
				activeTransmissions[transmission] = (progress, Data(capacity: Int(size)))
			}
			
		case CBUUID.PortraitSignatureCharacteristicID:
			guard let peerID = peerID(of: peripheral) else { break }
			portraitSignatures[peerID] = chunk
		case CBUUID.BiographySignatureCharacteristicID:
			guard let peerID = peerID(of: peripheral) else { break }
			biographySignatures[peerID] = chunk
		default:
			guard let peerID = peerID(of: peripheral) else { return }
			if cachedPeers[peerID] != nil {
				if transmission.characteristicID == CBUUID.LastChangedCharacteristicID {
					let knownState = cachedPeers[peerID]!.lastChanged
					cachedPeers[peerID]!.lastChangedData = chunk
					if cachedPeers[peerID]!.lastChanged > knownState {
						// the peer has a newer state then the one we cached, so reload all changeable properties
						guard let characteristics = peripheral.peereeService?.get(characteristics: [CBUUID.AggregateCharacteristicID, CBUUID.NicknameCharacteristicID, CBUUID.PeerIDSignatureCharacteristicID, CBUUID.AggregateSignatureCharacteristicID, CBUUID.NicknameSignatureCharacteristicID, CBUUID.LastChangedCharacteristicID]) else { break }
						peripheral.readValues(for: characteristics)
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
				if peerData.canConstruct {
					peerInfoTransmissions.removeValue(forKey: peerID)
					if let peer = peerData.construct(with: peerID) {
						cachedPeers[peerID] = peer
						peerData.progress.completedUnitCount = peerData.progress.totalUnitCount
						peerAppeared(peerID, peripheral: peripheral, again: false)
					} else {
						NSLog("WARN: Creating peer info failed, disconnecting.")
						// peer info is essential
						disconnect(peripheral)
					}
				} else {
					peerInfoTransmissions[peerID] = peerData
				}
			}
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
		guard error == nil else {
			NSLog("Error changing notification state: \(error!.localizedDescription)")
			if !characteristic.isNotifying {
				cancelTransmission(to: peripheral, of: characteristic.uuid)
			}
			return
		}
		
		if (characteristic.isNotifying) {
			NSLog("Notification began on \(characteristic.uuid.uuidString).")
		} else {
			NSLog("Notification stopped on \(characteristic.uuid.uuidString).")
		}
	}
	
	#if os(iOS)
	func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
		NSLog("Did read RSSI \(RSSI) of peripheral \(peripheral).")
		guard let peerID = peerID(of: peripheral) else { assertionFailure(); return }
		remotePeerDelegates[peerID]?.didRange(peerID, rssi: RSSI, error: error)
	}
	#else
	func peripheralDidUpdateRSSI(_ peripheral: CBPeripheral, error: Error?) {
		guard let peerID = peerID(of: peripheral) else { assertionFailure(); return }
		remotePeerDelegates[peerID]?.didRange(peerID, rssi: peripheral.rssi, error: error)
	}
	#endif
	
	func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
		NSLog("Peripheral transitioned from services \(invalidatedServices) to \(String(describing: peripheral.services)).")
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
			NSLog("Error writing \(characteristic.uuid.uuidString.left(8)) to PeerID \(peerID(of: peripheral)?.uuidString.left(8) ?? "unknown"): \(error!.localizedDescription).")
			return
		}
		guard let peerID = peerID(of: peripheral) else { return }
		if characteristic.uuid == CBUUID.AuthenticationCharacteristicID {
			guard getPeerInfo(of: peerID) != nil else { return }
			// if we loaded the peer info, we can store the verification state
			// if it is not loaded, reading the signed nonce is initiated on load
			peripheral.readValue(for: characteristic)
		} else if characteristic.uuid == CBUUID.RemoteAuthenticationCharacteristicID {
			remotePeerDelegates[peerID]?.didRemoteVerify(peerID)
		}
	}
	
	func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
		NSLog("Peripheral \(peripheral) did update name")
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
	
	private func peerAppeared(_ peerID: PeerID, peripheral: CBPeripheral, again: Bool) {
		verify(peerID)
		remotePeerDelegates[peerID] = delegate?.peerAppeared(peerID, again: again)
	}
	
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
		let randomByteCount = min(peripheral.maximumWriteValueLength(for: writeType), UserPeerManager.instance.keyPair.blockSize)
		do {
			let nonce = try generateRandomData(length: randomByteCount)
			nonces[peripheral] = nonce
			peripheral.writeValue(nonce, for: characteristic, type: writeType)
		} catch let error {
			remotePeerDelegates[peerID]?.failedVerification(of: peerID, error: error)
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

