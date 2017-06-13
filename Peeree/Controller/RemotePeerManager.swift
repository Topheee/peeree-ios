//
//  RemotePeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.10.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import CoreGraphics
import CoreBluetooth

protocol RemotePeerManagerDelegate {
//    func scanningStarted()
//    func scanningStopped()
    func peerAppeared(_ peerID: PeerID, again: Bool)
    func peerDisappeared(_ peerID: PeerID)
    func shouldIndicatePinMatch(to peer: PeerInfo) -> Bool
    func didRange(_ peerID: PeerID, rssi: NSNumber?, error: Error?)
    func failedVerification(of peerID: PeerID, error: Error)
    func didVerify(_ peerID: PeerID)
}

/// The RemotePeerManager singleton serves as an globally access point for information about all remote peers, whether they are currently in network range or were pinned in the past.
final class RemotePeerManager: PeerManager, RemotePeering, CBCentralManagerDelegate, CBPeripheralDelegate {
    static private let PeersMetKey = "PeersMet"
    
    private struct PeerData {
        var progress = Progress(totalUnitCount: 3)
        var aggregateData: Data? = nil
        var nicknameData: Data? = nil
        var publicKeyData: Data? = nil
        var lastChangedData: Data? = nil
        
        mutating func set(data: Data, for characteristicID: CBUUID) {
            switch characteristicID {
            case CBUUID.AggregateCharacteristicID:
                aggregateData = data
            case CBUUID.NicknameCharacteristicID:
                nicknameData = data
            case CBUUID.LastChangedCharacteristicID:
                lastChangedData = data
            case CBUUID.PublicKeyCharacteristicID:
                lastChangedData = data
            default:
                break
            }
            var count = Int64(0)
            for datum in [aggregateData, nicknameData, publicKeyData] {
                if datum != nil {
                    count += Int64(1)
                }
            }
            progress.completedUnitCount = count
        }
    }
    
    private let dQueue = DispatchQueue(label: "com.peeree.remotepeermanager_q", attributes: [])
    
	///	Since bluetooth connections are not very durable, all peers and their images are cached.
    private var cachedPeers = SynchronizedDictionary<PeerID, /* LocalPeerInfo */ PeerInfo>()
    private var peerInfoTransmissions = [PeerID : PeerData]()
    
    private var activeTransmissions = [Transmission : (Progress, Data)]() // TODO if the synchronization through the dQueue is too slow, switch to a delegate model, where the delegate is being told when a transmission begins/ends. Also, inform new delegates (via didSet and then dQueue.aysnc) of ongoing transmissions by calling transmissionDidBegin for every current transmission.
    
    private var centralManager: CBCentralManager!
    
	///	All readable remote peers the app is currently connected to. The keys are updated immediately when a new peripheral shows up, as we have to keep a reference to it. However, the values are not filled until the peripheral tell's us his ID.
    private var _availablePeripherals = [CBPeripheral : PeerID?]()
    /// Maps the identifieres of peripherals to the IDs of the peers they represent.
    private var peripheralPeerIDs = SynchronizedDictionary<PeerID, CBPeripheral>()
    
    private var nonces = [CBPeripheral : Data]()
    
    lazy var peersMet = UserDefaults.standard.integer(forKey: RemotePeerManager.PeersMetKey)
    
    var delegate: RemotePeerManagerDelegate?
    
    var availablePeers: [PeerID] {
        return peripheralPeerIDs.accessSync { (dictionary) in
            return dictionary.flatMap({ (peerID, peripheral) -> PeerID? in
                if peripheral.services == nil || peripheral.services!.isEmpty {
                    return nil
                } else {
                    return peerID
                }
            })
        }
    }
    
    var isBluetoothOn: Bool { return centralManager.state == .poweredOn }
    
    var isScanning: Bool {
        #if compile_iOS
            return centralManager.isScanning
        #else
            return true // shitty shit is not available on mac - what the fuck?
        #endif
    }
    
    func scan() {
        #if compile_iOS
            guard !isScanning else { return }
        #endif
        
        centralManager.scanForPeripherals(withServices: [CBUUID.PeereeServiceID], options: nil)
//        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    func stopScan() {
        guard isScanning else { return }
        
        dQueue.async {
            self.centralManager.stopScan()
            for (_, (progress, _)) in self.activeTransmissions {
                progress.cancel()
            }
            self.activeTransmissions.removeAll()
            self.peerInfoTransmissions.removeAll()
            // writing peersMet here is a good choice, since we will stop peering before the app is quit and also this method won't get called often and the peers met are not that critical
            UserDefaults.standard.set(self.peersMet, forKey:RemotePeerManager.PeersMetKey)
            for (peripheral, _) in self._availablePeripherals {
                self.disconnect(peripheral)
            }
            self._availablePeripherals.removeAll()
            self.nonces.removeAll()
            self.peripheralPeerIDs.removeAll() // does this make sense?
            self.clearCache()
        }
    }
    
    // characteristicID is ! because CBMutableCharacteristic.uuid is fucking optional on macOS
    private func load(characteristicID: CBUUID!, of peerID: PeerID) -> Progress? {
        guard isScanning else { return nil }
        guard let peripheral = peripheralPeerIDs[peerID] else { return nil }
        
        return dQueue.sync {
            if let progress = isLoading(characteristicID: characteristicID, of: peripheral) {
                return progress
            } else {
                guard let characteristic = (peripheral.peereeService?.characteristics?.first { $0.uuid == characteristicID }) else {
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
    
    func loadPicture(of peer: PeerInfo) -> Progress? {
        guard peer.hasPicture && peer.cgPicture == nil else { return nil }
        return load(characteristicID: CBUUID.PortraitCharacteristicID, of: peer.peerID)
    }
    
    func isPictureLoading(of peerID: PeerID) -> Progress? {
        guard let peripheral = peripheralPeerIDs[peerID] else { return nil }
        return isLoading(characteristicID: CBUUID.PortraitCharacteristicID, of: peripheral)
    }
    
    func isPeerInfoLoading(of peerID: PeerID) -> Progress? {
        guard let transmission = peerInfoTransmissions[peerID] else { return nil /* we load it anyway, so do not read again */ }
        return transmission.progress
    }
    
    func getPeerInfo(of peerID: PeerID) -> PeerInfo? {
        return cachedPeers[peerID]
    }
    
    func indicatePinMatch(to peer: PeerInfo) {
        guard delegate?.shouldIndicatePinMatch(to: peer) ?? false else { return }
        guard let peripheral = peripheralPeerIDs[peer.peerID] else { return }
        guard let characteristic = (peripheral.peereeService?.characteristics?.first { $0.uuid == CBUUID.PinMatchIndicationCharacteristicID }) else { return }
        
        peripheral.writeValue(pinnedData(true), for: characteristic, type: .withoutResponse)
    }
    
    func range(_ peerID: PeerID) {
        guard let peripheral = peripheralPeerIDs[peerID] else { return }
        peripheral.readRSSI()
    }
    
    func verify(_ peerID: PeerID) {
        guard let peripheral = peripheralPeerIDs[peerID], let characteristic = peripheral.peereeService?.getCharacteristics(withIDs: [CBUUID.AuthenticationCharacteristicID])?.first else { return }
        writeNonce(to: peripheral, characteristic: characteristic)
    }
    
    func clearCache() {
        cachedPeers.removeAll()
    }
    
    // MARK: CBCentralManagerDelegate
    
    /*!
     *  @method centralManagerDidUpdateState:
     *
     *  @param central  The central manager whose state has changed.
     *
     *  @discussion     Invoked whenever the central manager's state has been updated. Commands should only be issued when the state is
     *                  <code>CBCentralManagerStatePoweredOn</code>. A state below <code>CBCentralManagerStatePoweredOn</code>
     *                  implies that scanning has stopped and any connected peripherals have been disconnected. If the state moves below
     *                  <code>CBCentralManagerStatePoweredOff</code>, all <code>CBPeripheral</code> objects obtained from this central
     *                  manager become invalid and must be retrieved or discovered again.
     *
     *  @see            state
     *
     */
    @available(iOS 5.0, *)
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
//        if central.state != .poweredOn {
//            delegate?.scanningStopped()
//        }
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
        NSLog("Discovered \(_availablePeripherals[peripheral] == nil ? "unknown" : "known") peripheral \(peripheral).")
        guard _availablePeripherals[peripheral] == nil else { return }
        
        _availablePeripherals.updateValue(nil, forKey: peripheral)
        
        central.connect(peripheral, options: nil) // TODO examine options again
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        NSLog("Connected to peripheral \(peripheral)")
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID.PeereeServiceID])
//        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // error is set when the peripheral disconnected without us having called disconnectPeripheral before, so in almost all cases...
        for characteristicID in CBUUID.SplitCharacteristicIDs {
            cancelTransmission(to: peripheral, of: characteristicID)
        }
        _ = nonces.removeValue(forKey: peripheral)
        guard let _peerID = _availablePeripherals.removeValue(forKey: peripheral) else { return }
        guard let peerID = _peerID else { return }
        if let peerData = peerInfoTransmissions.removeValue(forKey: peerID) {
            peerData.progress.cancel()
        }
        _ = peripheralPeerIDs.removeValue(forKey: peerID)
        delegate?.peerDisappeared(peerID)
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
//            peripheral.discoverCharacteristics(nil, for:service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            NSLog("Error discovering characteristics: \(error!.localizedDescription)")
            disconnect(peripheral)
            return
        }

        var found = service.uuid != CBUUID.PeereeServiceID // only search for uuid characteristic in the top service
        // Again, we loop through the array, just in case.
        for characteristic in service.characteristics! {
            // And check if it's the right one
            NSLog("Peripheral \(peripheral.identifier): Discovered characteristic \(characteristic.uuid.uuidString) of service \(service.uuid.uuidString)")
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
            if characteristic.uuid == CBUUID.LocalUUIDCharacteristicID {
                // If it is, read it
                peripheral.readValue(for: characteristic)
                found = true
            } else if characteristic.uuid == CBUUID.RemoteUUIDCharacteristicID {
                NSLog("Writing peer id \(UserPeerInfo.instance.peer.peerID.uuidString).")
                peripheral.writeValue(UserPeerInfo.instance.peer.idData, for: characteristic, type: .withResponse)
            } else if characteristic.uuid == CBUUID.AuthenticationCharacteristicID {
                writeNonce(to: peripheral, characteristic: characteristic)
            } else if characteristic.uuid == CBUUID.PublicKeyCharacteristicID {
                peripheral.readValue(for: characteristic)
            }
        }
        
        if !found {
            NSLog("No UUID characteristic found on peripheral \(peripheral).")
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            NSLog("Error receiving characteristic \(characteristic.uuid.uuidString) update: \(error!.localizedDescription)")
            cancelTransmission(to: peripheral, of: characteristic.uuid)
            if characteristic.uuid == CBUUID.AuthenticationCharacteristicID {
                // TODO examine error
                guard let peerID = peerID(of: peripheral) else { return }
                delegate?.failedVerification(of: peerID, error: error!)
            }
            return
        }
        guard let chunk = characteristic.value else { return }
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
        
        // Have we got everything we need?
        if activeTransmissions[transmission]?.1.count == Int(progress.totalUnitCount) {
            switch characteristic.uuid {
            case CBUUID.PortraitCharacteristicID:
                guard let peerID = peerID(of: peripheral) else {
                    NSLog("Loaded portrait of unknown peripheral \(peripheral).")
                    break
                }
                guard let image = CGImage(jpegDataProviderSource: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent) else {
                    NSLog("Failed to create image with data \(data).")
                    break
                }
                cachedPeers[peerID]?.cgPicture = image
            default:
                break
            }
            
            // Cancel our subscription to the characteristic
            peripheral.setNotifyValue(false, for: characteristic)
        }
        
        progress.completedUnitCount = Int64(activeTransmissions[transmission]?.1.count ?? 0)
    }
    
    private var malformedTimer: Timer?
    private func processFirstChunk(_ chunk: Data, transmission: Transmission, peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        switch transmission.characteristicID {
        case CBUUID.LocalUUIDCharacteristicID:
            guard let peerID = PeerID(data: chunk) else {
                NSLog("Retrieved malformed peer ID. Disconnecting peer \(peripheral).")
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
            _availablePeripherals[peripheral] = peerID
            peripheralPeerIDs[peerID] = peripheral
            if cachedPeers[peerID] == nil {
                peersMet = peersMet + 1
                guard let characteristics = peripheral.peereeService?.getCharacteristics(withIDs: [CBUUID.AggregateCharacteristicID, CBUUID.LastChangedCharacteristicID, CBUUID.NicknameCharacteristicID, CBUUID.PublicKeyCharacteristicID]) else { break }
                peripheral.readValues(for: characteristics)
            } else {
                // we discovered this one earlier but he went offline in between (modified services to nil or empty, resp.) but now he is back online again
                peerAppeared(peerID, peripheral: peripheral, again: true)
            }
            
        case CBUUID.AuthenticationCharacteristicID:
            let signature = chunk
            guard let nonce = nonces.removeValue(forKey: peripheral), let peerID = peerID(of: peripheral), let peer = getPeerInfo(of: peerID) else {
                break
            }
            
            do {
                try peer.publicKey.verify(message: nonce, signature: signature)
                cachedPeers[peerID]?.verified = true
                delegate?.didVerify(peerID)
            } catch {
                cachedPeers[peerID]?.verified = false
                delegate?.failedVerification(of: peerID, error: error)
            }
            
        case CBUUID.PortraitCharacteristicID:
            var size: SplitCharacteristicSize = 0
            withUnsafeMutableBytes(of: &size) { pointer in
                pointer.copyBytes(from: chunk)
            }
            if let (progress, _) = activeTransmissions[transmission] {
                progress.totalUnitCount = Int64(size)
            } else {
                let progress = Progress(totalUnitCount: Int64(size))
                activeTransmissions[transmission] = (progress, Data(capacity: Int(size)))
            }
            
        case CBUUID.PublicKeyCharacteristicID:
            guard let peerID = peerID(of: peripheral) else { return }
            cachedPeers[peerID]?.setCharacteristicValue(of: transmission.characteristicID, to: chunk)
            
        default:
            guard let peerID = peerID(of: peripheral) else { return }
            if cachedPeers[peerID] != nil {
                cachedPeers[peerID]!.setCharacteristicValue(of: transmission.characteristicID, to: chunk)
            } else {
                var peerData = peerInfoTransmissions[peerID] ?? PeerData()
                peerData.set(data: chunk, for: transmission.characteristicID)
                if peerData.aggregateData != nil && peerData.nicknameData != nil && peerData.publicKeyData != nil {
                    if let peer = PeerInfo(peerID: peerID, publicKeyData: peerData.publicKeyData!, aggregateData: peerData.aggregateData!, nicknameData: peerData.nicknameData!, lastChangedData: peerData.lastChangedData) {
                        cachedPeers[peerID] = peer /* LocalPeerInfo(peer: peer) */
                        peerData.progress.completedUnitCount = peerData.progress.totalUnitCount
                        peerAppeared(peerID, peripheral: peripheral, again: false)
                        // always send pin match indication on new connect to be absolutely sure that the other really got that
                        indicatePinMatch(to: peer)
                    } else {
                        NSLog("Creating peer info failed, disconnecting.")
                        // peer info is essential
                        disconnect(peripheral)
                    }
                } else {
                    peerInfoTransmissions[peerID] = peerData
                }
            }
        }
    }
    
    private func peerAppeared(_ peerID: PeerID, peripheral: CBPeripheral, again: Bool) {
        cachedPeers[peerID]?.verified = false
        guard let characteristics = peripheral.peereeService?.getCharacteristics(withIDs: [CBUUID.AuthenticationCharacteristicID]) else {
            NSLog("Could not find auth characteristic")
            disconnect(peripheral)
            return
        }
        peripheral.readValues(for: characteristics)
        delegate?.peerAppeared(peerID, again: true)
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
        delegate?.didRange(peerID, rssi: RSSI, error: error)
    }
    #else
    func peripheralDidUpdateRSSI(_ peripheral: CBPeripheral, error: Error?) {
        guard let peerID = peerID(of: peripheral) else { assertionFailure(); return }
        delegate?.didRange(peerID, rssi: peripheral.rssi, error: error)
    }
    #endif
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        NSLog("Transitioned from services \(invalidatedServices) to \(String(describing: peripheral.services)).")
        guard let peerID = peerID(of: peripheral) else { return }
        if peripheral.services == nil || peripheral.services!.isEmpty {
//            disconnect(peripheral)
            delegate?.peerDisappeared(peerID)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            NSLog("Error writing \(characteristic.uuid) to Peer ID \(self.peerID(of: peripheral)?.uuidString ?? "unknown"): \(error!.localizedDescription).")
        }
        
        if characteristic.uuid == CBUUID.AuthenticationCharacteristicID {
            guard error != nil else {
                if peripheral.state == .connected {
                    // TODO evaluate error further
                    writeNonce(to: peripheral, characteristic: characteristic)
                }
                return
            }
        }
    }
    
    override init() {
        centralManager = nil
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: dQueue, options: [CBCentralManagerOptionShowPowerAlertKey : 1])
    }
    
    // MARK: Private Methods
    
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
    
    private func writeNonce(to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let randomByteCount = 63 // TODO find out and insert max bluetooth segment size
        var nonce = Data(count: randomByteCount)
        if nonce.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, randomByteCount, $0) }) == 0 {
            nonces[peripheral] = nonce
            peripheral.writeValue(nonce, for: characteristic, type: .withResponse)
        } else {
            // TODO handle error more appropriately
            perror(nil)
        }
    }
}

struct Transmission: Hashable {
    let peripheralID: UUID
    let characteristicID: CBUUID
    
    var hashValue: Int {
        var hash = 23
        hash = Int.addWithOverflow(hash, peripheralID.hashValue).0 // TODO maybe do something else if an overflow occured
        hash = Int.addWithOverflow(Int.multiplyWithOverflow(hash, 31).0, characteristicID.hashValue).0
        return hash
    }
}

func ==(lhs: Transmission, rhs: Transmission) -> Bool {
    return lhs.peripheralID == rhs.peripheralID && lhs.characteristicID == rhs.characteristicID
}

