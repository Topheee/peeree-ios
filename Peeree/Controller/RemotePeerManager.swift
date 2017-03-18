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
    func peerAppeared(_ peerID: PeerID)
    func peerDisappeared(_ peerID: PeerID)
    func isPinned(_ peerID: PeerID) -> Bool
    func didPin(_ peerID: PeerID)
    func didFailPin(_ peerID: PeerID)
    func didRange(_ peerID: PeerID, rssi: NSNumber?, error: Error?)
}

/// The RemotePeerManager singleton serves as an globally access point for information about all remote peers, whether they are currently in network range or were pinned in the past.
final class RemotePeerManager: PeerManager, RemotePeering, CBCentralManagerDelegate, CBPeripheralDelegate {
    static private let PeersMetKey = "PeersMet"
    
    private struct PeerData {
        var progress = Progress(totalUnitCount: 3)
        var aggregateData: Data? = nil
        var nicknameData: Data? = nil
        var lastChangedData: Data? = nil
        
        mutating func set(data: Data, for characteristicID: CBUUID) {
            switch characteristicID {
            case CBUUID.AggregateCharacteristicID:
                aggregateData = data
            case CBUUID.NicknameCharacteristicID:
                nicknameData = data
            case CBUUID.LastChangedCharacteristicID:
                lastChangedData = data
            default:
                break
            }
            var count = Int64(0)
            for datum in [aggregateData, nicknameData] {
                if datum != nil {
                    count += Int64(1)
                }
            }
            progress.completedUnitCount = count
        }
    }
    
    private let dQueue = DispatchQueue(label: "com.peeree.remotepeermanager_q", attributes: [])
    
	///	Since bluetooth connections are not very durable, all peers and their images are cached.
    private var cachedPeers = SynchronizedDictionary<PeerID, LocalPeerInfo>()
    private var peerInfoTransmissions = [PeerID : PeerData]()
    
    private var activeTransmissions = [Transmission : (Progress, Data)]() // TODO if the synchronization through the dQueue is too slow, switch to a delegate model, where the delegate is being told when a transmission begins/ends. Also, inform new delegates (via didSet and then dQueue.aysnc) of ongoing transmissions by calling transmissionDidBegin for every current transmission.
    private var ongoingPins = SynchronizedSet<PeerID>()
    
    private var centralManager: CBCentralManager!
    
	///	All readable remote peers the app is currently connected to. The keys are updated immediately when a new peripheral shows up, as we have to keep a reference to it. However, the values are not filled until the peripheral tell's us his ID.
    private var _availablePeripherals = [CBPeripheral : PeerID?]()
    /// Maps the identifieres of peripherals to the IDs of the peers they represent.
    private var peripheralPeerIDs = SynchronizedDictionary<PeerID, CBPeripheral>()
    
    lazy var peersMet = UserDefaults.standard.integer(forKey: RemotePeerManager.PeersMetKey)
    
    var delegate: RemotePeerManagerDelegate?
    
    var availablePeers: [PeerID] {
        return peripheralPeerIDs.accessQueue.sync {
            return peripheralPeerIDs.dictionary.flatMap({ (peerID, _) -> PeerID? in // PERFORMANCE
                return peerID
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
            for (_, (progress, _)) in self.activeTransmissions {
                progress.cancel()
            }
            self.activeTransmissions.removeAll()
            self.peerInfoTransmissions.removeAll()
            // writing peersMet here is a good choice, since we will stop peering before the app is quit and also this method won't get called often and the peers met are not that critical
            UserDefaults.standard.set(self.peersMet, forKey:RemotePeerManager.PeersMetKey)
            self.centralManager.stopScan()
            for (peripheral, _) in self._availablePeripherals {
                self.disconnect(peripheral)
            }
            self._availablePeripherals.removeAll()
            self.peripheralPeerIDs.removeAll() // does this make sense?
            self.ongoingPins.accessQueue.async {
                for peerID in self.ongoingPins.set {
                    self.delegate?.didFailPin(peerID)
                }
                self.ongoingPins.set.removeAll() // TODO give pin points back
            }
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
                // TODO maybe search in the peripherals services and check whether we already subscribed
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
        return load(characteristicID: portraitCharacteristic.uuid, of: peer.peerID)
    }
    
//    func loadPeerInfo(of peerID: PeerID) -> Progress? {
//        guard getPeerInfo(of: peerID) == nil else { return nil }
//        guard let transmission = peerInfoTransmissions[peerID] else { return nil /* we load it anyway, so do not read again */ }
//        return transmission.progress
//    }
    
    func isPictureLoading(of peerID: PeerID) -> Progress? {
        guard let peripheral = peripheralPeerIDs[peerID] else { return nil }
        return isLoading(characteristicID: CBUUID.PortraitCharacteristicID, of: peripheral)
    }
    
    func isPeerInfoLoading(of peerID: PeerID) -> Progress? {
        guard let transmission = peerInfoTransmissions[peerID] else { return nil /* we load it anyway, so do not read again */ }
        return transmission.progress
    }
    
    func getPeerInfo(of peerID: PeerID) -> PeerInfo? {
        return cachedPeers[peerID]?.peer
    }
    
    func pin(_ peerID: PeerID) {
        guard !isPinning(peerID) else { return }
        ongoingPins.insert(peerID)
        guard let peripheral = peripheralPeerIDs[peerID] else {
            ongoingPins.remove(peerID)
            delegate?.didFailPin(peerID)
            return
        }
        let data = pinnedData(true)
        guard let characteristic = (peripheral.peereeService?.characteristics?.first { $0.uuid == pinnedCharacteristic.uuid }) else { return }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
    
    func isPinning(_ peerID: PeerID) -> Bool {
        return ongoingPins.contains(peerID)
    }
    
    func range(_ peerID: PeerID) {
        guard let peripheral = peripheralPeerIDs[peerID] else { return }
        peripheral.readRSSI()
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
        for characteristicID in CBUUID.splitCharacteristicIDs {
            cancelTransmission(to: peripheral, of: characteristicID)
        }
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
            
//            peripheral.discoverIncludedServices([CBUUID.PeerInfoServiceID], for: service)
            peripheral.discoverIncludedServices(nil, for: service)
            peripheral.discoverCharacteristics(peereeService.characteristics!.flatMap { $0.uuid }, for:service)
//            peripheral.discoverCharacteristics(nil, for:service)
            guard let peerID = peerID(of: peripheral) else { continue }
            guard getPeerInfo(of: peerID) != nil else { continue }
            // we discovered this one earlier but he went offline in between (modified services to nil or empty, resp.) but now he is back online again
            delegate?.peerAppeared(peerID)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        guard error == nil else {
            NSLog("Error discovering included services: \(error!.localizedDescription)")
            disconnect(peripheral)
            return
        }
        guard service.includedServices != nil && service.includedServices!.count > 0 else {
            NSLog("Found peripheral with no included services.")
            return
        }
        
        // Discover the characteristic we want...
        
        // Loop through the newly filled included services array, just in case there's more than one.
        for service in service.includedServices! {
            NSLog("Discovered included service \(service.uuid.uuidString).")
            guard service.uuid == CBUUID.PeerInfoServiceID else { continue }
            peripheral.discoverCharacteristics(peerInfoService.characteristics!.flatMap { $0.uuid }, for:service)
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
            if characteristic.uuid == CBUUID.UUIDCharacteristicID {
                // If it is, subscribe to it
                peripheral.readValue(for: characteristic)
                found = true
                peripheral.writeValue(UserPeerInfo.instance.peer.idData, for: characteristic, type: .withResponse)
            }
        }
        
        if !found {
            NSLog("No UUID characteristic found on peripheral \(peripheral).")
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            NSLog("Error updating characteristic value: \(error!.localizedDescription)")
            cancelTransmission(to: peripheral, of: characteristic.uuid)
            return
        }
        guard let chunk = characteristic.value else { return }
        let transmission = Transmission(peripheralID: peripheral.identifier, characteristicID: characteristic.uuid)
        
        guard let (progress, _) = activeTransmissions[transmission] else {
            // first chunk, udpated without request
            processFirstChunk(chunk, transmission: transmission, peripheral: peripheral)
            return
        }
        guard !progress.isCancelled else {
            if characteristic.isNotifying {
                peripheral.setNotifyValue(false, for: characteristic)
            }
            return
        }
        guard progress.totalUnitCount > 0 else {
            processFirstChunk(chunk, transmission: transmission, peripheral: peripheral)
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
                guard let peerInfo = cachedPeers[peerID] else { return }
                guard let image = CGImage(jpegDataProviderSource: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent) else {
                    NSLog("Failed to create image with data \(data).")
                    break
                }
                peerInfo.cgPicture = image
            default:
                break
            }
            
            // Cancel our subscription to the characteristic
            peripheral.setNotifyValue(false, for: characteristic)
        }
        
        progress.completedUnitCount = Int64(activeTransmissions[transmission]?.1.count ?? 0)
    }
    
    private func processFirstChunk(_ chunk: Data, transmission: Transmission, peripheral: CBPeripheral) {
        switch transmission.characteristicID {
        case CBUUID.UUIDCharacteristicID:
            guard let peerID = PeerID(data: chunk) else {
                assertionFailure()
                return
            }
            _availablePeripherals[peripheral] = peerID
            peripheralPeerIDs[peerID] = peripheral
            if cachedPeers[peerID] == nil {
                peersMet = peersMet + 1
                guard let characteristics = peripheral.peerInfoService?.characteristics else { break }
                peripheral.readValues(for: characteristics)
            }
            // always send pin on new connect to be absolutely sure that the other really got that
            if delegate?.isPinned(peerID) ?? false {
                guard let characteristic = (peripheral.peereeService?.characteristics?.first { $0.uuid == pinnedCharacteristic.uuid }) else {
                    assertionFailure("could not find pinned characteristic in services")
                    return
                }
                peripheral.writeValue(pinnedData(true), for: characteristic, type: .withoutResponse)
            }
        case CBUUID.PortraitCharacteristicID:
            var size: Int32 = 0
            var offset: Int32 = 0
            for byte in chunk {
                size += Int32(byte) << offset
                offset += 8
            }
            if let (progress, _) = activeTransmissions[transmission] {
                progress.totalUnitCount = Int64(size)
            } else {
                let progress = Progress(totalUnitCount: Int64(size))
                activeTransmissions[transmission] = (progress, Data(capacity: Int(size)))
            }
        default:
            guard let peerID = peerID(of: peripheral) else { return }
            if let peer = cachedPeers[peerID] {
                peer.peer.characteristicValue(for: transmission.characteristicID, to: chunk)
            } else {
                var peerData = peerInfoTransmissions[peerID] ?? PeerData()
                peerData.set(data: chunk, for: transmission.characteristicID)
                if peerData.aggregateData != nil && peerData.nicknameData != nil {
                    guard let peer = PeerInfo(peerID: peerID, aggregateData: peerData.aggregateData!, nicknameData: peerData.nicknameData!, lastChangedData: peerData.lastChangedData) else {
                        NSLog("Creating peer info failed, disconnecting.")
                        // peer info is essential
                        disconnect(peripheral)
                        return
                    }
                    cachedPeers[peerID] = LocalPeerInfo(peer: peer)
                    peerData.progress.completedUnitCount = peerData.progress.totalUnitCount
                    delegate?.peerAppeared(peerID)
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
        delegate?.didRange(peerID, rssi: RSSI, error: error)
    }
    #else
    func peripheralDidUpdateRSSI(_ peripheral: CBPeripheral, error: Error?) {
        guard let peerID = peerID(of: peripheral) else { assertionFailure(); return }
        delegate?.didRange(peerID, rssi: peripheral.rssi, error: error)
    }
    #endif
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        NSLog("Transitioned from services \(invalidatedServices) to \(peripheral.services). State: \(peripheral.state.rawValue).")
        guard let peerID = peerID(of: peripheral) else { return }
        if peripheral.services == nil || peripheral.services!.isEmpty {
//            disconnect(peripheral)
            delegate?.peerDisappeared(peerID)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let peerID = peerID(of: peripheral) else {
            NSLog("Did write value for \(characteristic) on peripheral with unknown Peer ID (\(error != nil ? error!.localizedDescription : "no error")).")
            return
        }
        if characteristic.uuid == pinnedCharacteristic.uuid {
            ongoingPins.remove(peerID)
            guard error == nil else {
                NSLog("Error during pin write - \(error!.localizedDescription).")
                delegate?.didFailPin(peerID)
                return
            }
            delegate?.didPin(peerID)
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
        guard peripheral.services != nil else {
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        for service in peripheral.services! {
            guard service.characteristics != nil else { continue }
            for characteristic in service.characteristics! {
                if characteristic.isNotifying {
                    peripheral.setNotifyValue(false, for: characteristic)
                }
            }
        }
        
        // If we've got this far, we're connected, but we're not subscribed, so we just disconnect
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

