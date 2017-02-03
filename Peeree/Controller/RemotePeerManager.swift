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
    func sessionHandlerReceivedPin(from: PeerID)
    func peerAppeared(_ peerID: PeerID)
    func peerDisappeared(_ peerID: PeerID)
}

/// The RemotePeerManager singleton serves as an globally access point for information about all remote peers, whether they are currently in network range or were pinned in the past.
final class RemotePeerManager: PeerManager, RemotePeering, CBCentralManagerDelegate, CBPeripheralDelegate {

    static private let PeersMetKey = "PeersMet"
    
    private enum PortraitProgressKey {
        case delegateKey
    }
	
	///	Since bluetooth connections are not very reliable, all peers and their images are cached.
    private var cachedPeers = SynchronizedDictionary<PeerID, LocalPeerInfo>()
    
    /// Bluetooth network handlers.
    private var centralManager: CBCentralManager!
    
    private var activeTransmissions = [Transmission : (Progress, Data)]()
    
	/*
	 *	All remote peers the app is currently connected to. This property is immediatly updated when a new connection is set up or an existing is cut off.
	 */
	private var _availablePeripherals = SynchronizedDictionary<PeerID, CBPeripheral>() // TODO eigentlich muss das nicht synced sein, sondern nur der getter unten, wie alle anderen auf die DispatchQueue von dem ganzen Teil hier
    /// Maps the identifieres of peripherals to the IDs of the peers they represent.
    private var peripheralPeerIDs = [UUID : PeerID]()
    
    var delegate: RemotePeerManagerDelegate?
    
    var availablePeripherals: [PeerID] {
        return _availablePeripherals.accessQueue.sync {
            _availablePeripherals.dictionary.flatMap({ (peerID, _) -> PeerID? in
                return peerID
            })
        }
    }
    
    var isBluetoothOn: Bool {
        return centralManager.state == .poweredOn
    }
    
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
        
        centralManager.scanForPeripherals(withServices: [CBUUID.BluetoothServiceID], options: nil)
    }

    func stopScan() {
        guard isScanning else { return }
        
        // TODO cancel connections
        // writing peersMet here is a good choice, since we will stop peering before the app is quit and also this method won't get called often and the peers met are not that critical
        UserDefaults.standard.set(peersMet, forKey:RemotePeerManager.PeersMetKey)
        centralManager.stopScan()
        _availablePeripherals.removeAll()
    }
    
    lazy var peersMet = UserDefaults.standard.integer(forKey: RemotePeerManager.PeersMetKey)
    
    private func load(characteristic: CBCharacteristic, of peerID: PeerID) -> Progress? {
        guard isScanning else { return nil }
        guard let peripheral = _availablePeripherals[peerID] else { return nil }
        
        if let progress = isLoading(characteristicID: characteristic.uuid, of: peripheral) {
            return progress
        } else {
            // TODO maybe search in the peripherals services and check whether we already subscribed
            peripheral.setNotifyValue(true, for: characteristic)
            let transmission = Transmission(peripheralID: peripheral.identifier, characteristic: characteristic.uuid)
            let progress = Progress(parent: nil, userInfo: nil)
            activeTransmissions[transmission] = (progress, Data())
            return progress
        }
    }
    
    private func isLoading(characteristicID: CBUUID, of peripheral: CBPeripheral) -> Progress? {
        return activeTransmissions[Transmission(peripheralID: peripheral.identifier, characteristic: characteristicID)]?.0
    }
    
    func loadPicture(of peer: PeerInfo) -> Progress? {
        guard peer.hasPicture && peer.cgPicture == nil else { return nil }
        return load(characteristic: portraitCharacteristic, of: peer.peerID)
    }
    
    func loadPeerInfo(of peerID: PeerID) -> Progress? {
        guard getPeerInfo(of: peerID) == nil else { return nil }
        return load(characteristic: peerInfoCharacteristic, of: peerID)
    }
    
    func isPictureLoading(of peerID: PeerID) -> Progress? {
        guard let peripheral = _availablePeripherals[peerID] else { return nil }
        return isLoading(characteristicID: CBUUID.PortraitCharacteristicID, of: peripheral)
    }
    
    func isPeerInfoLoading(of peerID: PeerID) -> Progress? {
        guard let peripheral = _availablePeripherals[peerID] else { return nil }
        return isLoading(characteristicID: CBUUID.PeerInfoCharacteristicID, of: peripheral)
    }
    
    func getPeerInfo(of peerID: PeerID) -> PeerInfo? {
        return cachedPeers[peerID]?.peer
    }
    
//    func clearCache() {
//        cachedPeers.removeAll()
//    }
    
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
        NSLog("Failed to connect to \(peripheral). (\(error?.localizedDescription))")
        disconnect(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard _availablePeripherals[peripheral.identifier] == nil else { return }
        
        _availablePeripherals[peripheral.identifier] = peripheral
        
        central.connect(peripheral, options: nil) // TODO examine options again
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID.BluetoothServiceID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        NSLog("Peripheral Disconnected (\(error))")
        removePeripheral(peripheral)
        delegate?.peerDisappeared(peripheral.identifier)
    }
    
    // MARK: CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error != nil else {
            NSLog("Error discovering services: \(error!.localizedDescription)")
            disconnect(peripheral)
            return
        }
        
        // Discover the characteristic we want...
        
        // Loop through the newly filled peripheral.services array, just in case there's more than one.
        for service in peripheral.services! {
            peripheral.discoverCharacteristics([CBUUID.UUIDCharacteristicID], for:service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error != nil else {
            NSLog("Error discovering characteristics: \(error!.localizedDescription)")
            disconnect(peripheral)
            return
        }

        var found = false
        // Again, we loop through the array, just in case.
        for characteristic in service.characteristics! {
            // And check if it's the right one
            if characteristic == peerUUIDCharacteristic || characteristic == pinnedCharacteristic {
                // If it is, subscribe to it
                peripheral.setNotifyValue(true, for: characteristic)
                found = found || characteristic == peerUUIDCharacteristic
            }
        }
        
        if !found {
            assertionFailure("No UUID characteristic found")
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error != nil else {
            NSLog("Error updating characteristic value: \(error!.localizedDescription)")
            cancelTransmission(to: peripheral, of: characteristic.uuid)
            return
        }
        guard let chunk = characteristic.value else { return }
        let transmission = Transmission(peripheralID: peripheral.identifier, characteristic: CBUUID.PortraitCharacteristicID)
        
        guard let (progress, data) = activeTransmissions[transmission] else {
            // first chunk, udpated without request
            processFirstChunk(chunk, transmission: transmission)
            return
        }
        guard !progress.isCancelled else {
            peripheral.setNotifyValue(false, for: characteristic)
            return
        }
        guard progress.totalUnitCount > 0 else {
            processFirstChunk(chunk, transmission: transmission)
            return
        }
        let stringFromData = String(data: chunk, encoding: String.Encoding.utf8)
        
        // Have we got everything we need?
        if stringFromData == "EOM" {
            switch characteristic.uuid {
            case CBUUID.PeerInfoCharacteristicID:
                guard let peerInfo = NSKeyedUnarchiver.unarchiveObject(with: data) as? NetworkPeerInfo else { return }
                cachedPeers[peerInfo.peer.peerID] = LocalPeerInfo(peer: peerInfo.peer)
            case CBUUID.PortraitCharacteristicID:
                guard let peerInfo = cachedPeers[peripheral.identifier] else { return }
                guard let image = CGImage(jpegDataProviderSource: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent) else { return }
                
                peerInfo.cgPicture = image
            default:
                break
            }
            
            // Cancel our subscription to the characteristic
            peripheral.setNotifyValue(false, for: characteristic)
            progress.completedUnitCount = progress.totalUnitCount
        } else {
            // Otherwise, just add the data on to what we already have
            activeTransmissions[transmission]?.1.append(chunk)
            progress.completedUnitCount = Int64(activeTransmissions[transmission]?.1.count ?? 0)
        }
        
        // Log it
        NSLog("Received: \(stringFromData)")
    }
    
    func processFirstChunk(_ chunk: Data, transmission: Transmission) {
        switch transmission.characteristic {
        case CBUUID.UUIDCharacteristicID:
            guard let string = String(data: chunk, encoding: String.Encoding.ascii) else {
                assertionFailure()
                return
            }
            guard let peerID = PeerID(uuidString: string) else {
                assertionFailure()
                return
            }
            delegate?.peerAppeared(peerID)
            if cachedPeers[peerID] == nil {
                peersMet = peersMet + 1
                //                peripheral.setNotifyValue(true, for: peerInfoCharacteristic)
            }
        case CBUUID.PeerInfoCharacteristicID, CBUUID.PortraitCharacteristicID:
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
                activeTransmissions[transmission] = (progress, Data())
            }
        case CBUUID.PinnedCharacteristicID:
            guard chunk.first != 0 else { return }
            delegate?.sessionHandlerReceivedPin(from: transmission.peripheralID)
        default:
            break
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error != nil else {
            NSLog("Error changing notification state: \(error!.localizedDescription)")
            if !characteristic.isNotifying {
                cancelTransmission(to: peripheral, of: characteristic.uuid)
            }
            return
        }
        guard characteristic.uuid.isCharacteristicID else { return }
        
        if (characteristic.isNotifying) {
            NSLog("Notification began on \(characteristic)")
        } else {
            NSLog("Notification stopped on \(characteristic).  Disconnecting")
        }
    }
    
    // MARK: Private Methods
    
    override init() {
        centralManager = nil
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.global(), options: [CBCentralManagerOptionShowPowerAlertKey : 1])
    }
    
    private func disconnect(_ peripheral: CBPeripheral) {
        // Don't do anything if we're not connected
        guard peripheral.state == .connected || peripheral.state == .connecting else { return }
        
        // See if we are subscribed to a characteristic on the peripheral
        guard peripheral.services != nil else { return }
        for service in peripheral.services! {
            guard service.characteristics != nil else { continue }
            for characteristic in service.characteristics! {
                guard characteristic.uuid.isCharacteristicID && characteristic.isNotifying else {
                    continue
                }
                // It is notifying, so unsubscribe
                peripheral.setNotifyValue(false, for: characteristic)
                // And we're done.
                return
            }
        }
        
        // If we've got this far, we're connected, but we're not subscribed, so we just disconnect
        centralManager.cancelPeripheralConnection(peripheral)
    }
        
    private func cancelTransmission(to peripheral: CBPeripheral, of characteristicID: CBUUID) {
        let transmission = Transmission(peripheralID: peripheral.identifier, characteristic: characteristicID)
        guard let (progress, _) = activeTransmissions.removeValue(forKey: transmission) else { return }
        
        progress.cancel()
    }
    
    private func removePeripheral(_ peripheral: CBPeripheral) {
        for characteristicID in CBUUID.characteristicIDs {
            cancelTransmission(to: peripheral, of: characteristicID)
        }
        guard let peerID = peripheralPeerIDs.removeValue(forKey: peripheral.identifier) else { return }
        _ = _availablePeripherals.removeValueForKey(peerID)
    }
}

//fileprivate final class RemotePeer: NSObjectProtocol {
//    let peripheral: CBPeripheral
//    var peerInfo: LocalPeerInfo?
//    
//    private var servicesDiscovered = false
//}

struct Transmission: Hashable {
    let peripheralID: UUID
    let characteristic: CBUUID
    
    var hashValue: Int {
        var hash = 23
        hash = hash * 31 + peripheralID.hashValue
        hash = hash * 31 + characteristic.hashValue
        return hash
    }
}

func ==(lhs: Transmission, rhs: Transmission) -> Bool {
    return lhs.peripheralID == rhs.peripheralID && lhs.characteristic == rhs.characteristic
}

