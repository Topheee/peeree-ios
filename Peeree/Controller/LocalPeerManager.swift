//
//  LocalPeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth

protocol LocalPeerManagerDelegate {
    func advertisingStarted()
    func advertisingStopped()
//    func networkTurnedOff()
    func receivedPinMatchIndication(from: PeerID)
}

/// The LocalPeerManager singleton serves as delegate of the local peripheral manager to supply information about the local peer to connected peers.
/// All the CBPeripheralManagerDelegate methods work on a separate queue so you must not call them yourself.
final class LocalPeerManager: PeerManager, CBPeripheralManagerDelegate {
    let dQueue = DispatchQueue(label: "com.peeree.localpeermanager_q", attributes: [])
    
    private var peripheralManager: CBPeripheralManager! = nil
    
    private var interruptedTransfers: [(Data, CBMutableCharacteristic, CBCentral, Bool)] = []
    
    // unfortunenately this will grow until we go offline as we do not get any disconnection notification...
    // also, we CAN NOT rely on that the central really is the peer behind that PeerID, as we have no mechanism to prove it
    private var _availableCentrals = SynchronizedDictionary<UUID, PeerID>(queueLabel: "\(Bundle.main.bundleIdentifier!).availableCentrals")
    
    private var nonces = [UUID : Data]()
    
    var delegate: LocalPeerManagerDelegate?
    
    var isAdvertising: Bool {
//        return dQueue.sync {
            return peripheralManager != nil //&& peripheralManager.isAdvertising
//        }
    }
    
    func startAdvertising() {
        guard !isAdvertising else { return }
        
        #if os(iOS)
        peripheralManager = CBPeripheralManager(delegate: self, queue: dQueue, options: [CBPeripheralManagerOptionRestoreIdentifierKey : "PeripheralManager"])
        #else
        peripheralManager = CBPeripheralManager(delegate: self, queue: dQueue, options: nil)
        #endif
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
        _ = _availableCentrals.removeValue(forKey: cbPeerID)
    }
    
    // MARK: CBPeripheralManagerDelegate
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        // both always the same
//        let services = dict[CBPeripheralManagerRestoredStateServicesKey]
//        let advertisementData = dict[CBPeripheralManagerRestoredStateAdvertisementDataKey]
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            NSLog("Adding service \(service.uuid.uuidString) failed (\(error!.localizedDescription)). - Stopping advertising.")
            stopAdvertising()
            return
        }
        
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [CBUUID.PeereeServiceID]])
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
            // value: UserPeerInfo.instance.peer.idData
            let localUUIDCharacteristic = CBMutableCharacteristic(type: CBUUID.LocalUUIDCharacteristicID, properties: [.read], value: UserPeerInfo.instance.peer.idData, permissions: [.readable])
            // value: remote peer.idData
            let remoteUUIDCharacteristic = CBMutableCharacteristic(type: CBUUID.RemoteUUIDCharacteristicID, properties: [.write], value: nil, permissions: [.writeable])
            // value: Data(count: 1)
            let pinnedCharacteristic = CBMutableCharacteristic(type: CBUUID.PinMatchIndicationCharacteristicID, properties: [.write], value: nil, permissions: [.writeable])
            // value try? Data(contentsOf: UserPeerInfo.instance.pictureResourceURL)
            let portraitCharacteristic = CBMutableCharacteristic(type: CBUUID.PortraitCharacteristicID, properties: [.indicate], value: nil, permissions: [])
            // value: aggregateData
            let aggregateCharacteristic = CBMutableCharacteristic(type: CBUUID.AggregateCharacteristicID, properties: [.read], value: UserPeerInfo.instance.peer.aggregateData, permissions: [.readable])
            // value: lastChangedData
            let lastChangedCharacteristic = CBMutableCharacteristic(type: CBUUID.LastChangedCharacteristicID, properties: [.read], value: UserPeerInfo.instance.peer.lastChangedData, permissions: [.readable])
            // value nicknameData
            let nicknameCharacteristic = CBMutableCharacteristic(type: CBUUID.NicknameCharacteristicID, properties: [.read], value: UserPeerInfo.instance.peer.nicknameData, permissions: [.readable])
            // value UserPeerInfo.instance.peer.publicKey
            let publicKeyCharacteristic = CBMutableCharacteristic(type: CBUUID.PublicKeyCharacteristicID, properties: [.read], value: UserPeerInfo.instance.peer.publicKeyData, permissions: [.readable])
            // value nonce when read, signed nonce when written
            // Version 2: value with public key of peer encrypted nonce when read, signed nonce encrypted with user's public key when written
            let authCharacteristic = CBMutableCharacteristic(type: CBUUID.AuthenticationCharacteristicID, properties: [.read, .write], value: nil, permissions: [.readable, .writeable])
            
            let peereeService = CBMutableService(type: CBUUID.PeereeServiceID, primary: true)
            peereeService.characteristics = [localUUIDCharacteristic, remoteUUIDCharacteristic, pinnedCharacteristic, portraitCharacteristic, aggregateCharacteristic, lastChangedCharacteristic, nicknameCharacteristic, publicKeyCharacteristic, authCharacteristic]
            peripheralManager.add(peereeService)
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard let theError = error else {
            delegate?.advertisingStarted()
            return
        }
        
        NSLog("ERR: Failed to start advertising. (\(theError.localizedDescription))")
        stopAdvertising()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        NSLog("Central read size: \(central.maximumUpdateValueLength)")
        switch characteristic.uuid {
        case CBUUID.PortraitCharacteristicID:
            do {
                let data = try Data(contentsOf: UserPeerInfo.instance.pictureResourceURL)
                sendData(data: data, of: characteristic as! CBMutableCharacteristic, to: central, sendSize: true)
            } catch {
                NSLog("ERR: Failed to read user portrait: \(error.localizedDescription)")
                NSLog("Removing picture from user info.")
                UserPeerInfo.instance.peer.cgPicture = nil
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
            sendData(data: data, of: characteristic, to: central, sendSize: sendSize)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        NSLog("Did receive read on \(request.characteristic.uuid.uuidString.left(8)) from central \(request.central.identifier)")
        if let data = UserPeerInfo.instance.peer.getCharacteristicValue(of: request.characteristic.uuid) {
            // dead code, as we provided those values when we created the mutable characteristics
            if (request.offset > data.count) {
                peripheral.respond(to: request, withResult: .invalidOffset)
            } else {
                request.value = data.subdata(in: request.offset..<data.count - request.offset)
                peripheral.respond(to: request, withResult: .success)
            }
        } else if request.characteristic.uuid == CBUUID.AuthenticationCharacteristicID {
            guard let nonce = nonces.removeValue(forKey: request.central.identifier) else {
                peripheral.respond(to: request, withResult: .insufficientResources)
                return
            }
            do {
                let signature = try UserPeerInfo.instance.keyPair.sign(message: nonce)

                if (request.offset > signature.count) {
                    peripheral.respond(to: request, withResult: .invalidOffset)
                } else {
                    request.value = signature.subdata(in: request.offset..<signature.count - request.offset)
                    peripheral.respond(to: request, withResult: .success)
                }
            } catch {
                NSLog("ERR: Signing failed: \(error)")
                peripheral.respond(to: request, withResult: .requestNotSupported)
            }
            
        } else {
            peripheral.respond(to: request, withResult: .readNotPermitted)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        var error: CBATTError.Code = .success
        var _peer: (PeerID, UUID)? = nil
        var _pin: (PeerID, Bool)? = nil
        var _nonce: (CBCentral, Data)? = nil
        for request in requests {
            NSLog("Did receive write on \(request.characteristic.uuid.uuidString.left(8)) from central \(request.central.identifier)")
            if request.characteristic.uuid == CBUUID.RemoteUUIDCharacteristicID {
                guard let data = request.value, let peerID = PeerID(data: data) else {
                    error = .insufficientResources
                    break
                }
                
                _peer = (peerID, request.central.identifier)
            } else if request.characteristic.uuid == CBUUID.PinMatchIndicationCharacteristicID {
                guard let data = request.value, let pinFlag = data.first, let peerID = _availableCentrals[request.central.identifier] else {
                    error = .insufficientResources
                    break
                }
                
                _pin = (peerID, pinFlag != 0)
            } else if request.characteristic.uuid == CBUUID.AuthenticationCharacteristicID {
                guard let nonce = request.value else {
                    error = .insufficientResources
                    break
                }
                
                _nonce = (request.central, nonce)
            } else {
                error = .writeNotPermitted
                break
            }
        }
        if error == .success {
            if let peer = _peer {
                _availableCentrals[peer.1] = peer.0
            }
            if let pin = _pin, pin.1 {
                // attack scenario: Eve sends us an indication with her or Bob's PeerID => we always validate with the server, and as we do not react to Eve directly, so Eve cannot derive sensitive information
                delegate?.receivedPinMatchIndication(from: pin.0)
            }
            if let nonce = _nonce {
                nonces[nonce.0.identifier] = nonce.1
            }
        }
        peripheral.respond(to: requests.first!, withResult: error)
    }
    
    // MARK: Private Methods
    
    private func sendData(data: Data, of characteristic: CBMutableCharacteristic, to central: CBCentral, sendSize: Bool) {
        if sendSize {
            // send the amount of bytes in data in the first package
            var size = SplitCharacteristicSize(data.count)
            
            let sizeData = Data(bytesNoCopy: &size, count: MemoryLayout<SplitCharacteristicSize>.size, deallocator: Data.Deallocator.none)
            guard peripheralManager.updateValue(sizeData, for: characteristic, onSubscribedCentrals: [central]) else {
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
            send = peripheralManager.updateValue(chunk, for: characteristic, onSubscribedCentrals: [central])
            
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
