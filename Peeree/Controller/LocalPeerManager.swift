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
    func receivedPin(from: PeerID)
}

/// The LocalPeerManager singleton serves as delegate of the local peripheral manager to supply information about the local peer to connected peers.
/// All the CBPeripheralManagerDelegate methods work on a separate queue so you must not call them yourself.
final class LocalPeerManager: PeerManager, CBPeripheralManagerDelegate {
    private let dQueue = DispatchQueue(label: "com.peeree.localpeermanager_q", attributes: [])
    
    private var peripheralManager: CBPeripheralManager! = nil
    
    private var interruptedTransfers: [(Data, CBMutableCharacteristic, CBCentral, Bool)] = []
    
    private var _availableCentrals = SynchronizedDictionary<CBCentral, PeerID>()
    
    var availablePeers: [PeerID] {
        return _availableCentrals.accessQueue.sync {
            _availableCentrals.dictionary.flatMap({ (_, peerID) -> PeerID? in // PERFORMANCE
                return peerID
            })
        }
    }
    
    var delegate: LocalPeerManagerDelegate?
    
    var isAdvertising: Bool {
        return peripheralManager != nil //&& peripheralManager.isAdvertising
    }
    
    func startAdvertising() {
        guard !isAdvertising else { return }
        
        peripheralManager = CBPeripheralManager(delegate: self, queue: dQueue, options: nil)
    }
    
    func stopAdvertising() {
        guard isAdvertising else { return }
        
        peripheralManager.stopAdvertising()
        peripheralManager = nil
        _availableCentrals.removeAll()
        // I think we don't have to do this here as it is done in didStartAdvertising
//        dQueue.async {
//            self.interruptedTransfers.removeAll()
//        }
        delegate?.advertisingStopped()
    }
    
    // MARK: CBPeripheralManagerDelegate
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            NSLog("Adding service \(service.uuid.uuidString) failed (\(error!.localizedDescription)).")
            return
        }
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .unknown, .resetting:
            // just wait
            break
        case .unsupported, .unauthorized:
            UserPeerInfo.instance.iBeaconUUID = nil
            stopAdvertising()
        case .poweredOff:
            stopAdvertising()
        case .poweredOn:
            UserPeerInfo.instance.iBeaconUUID = UUID()
            peripheralManager.add(peripheralService)
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [CBUUID.BluetoothServiceID]])
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard let theError = error else {
            interruptedTransfers.removeAll()
            delegate?.advertisingStarted()
            return
        }
        
        NSLog("Failed to start advertising. (\(theError.localizedDescription))")
        stopAdvertising()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        switch characteristic.uuid {
        case CBUUID.UUIDCharacteristicID:
            // this is dead code since subscribing is no longer possible to this characteristic
            guard let data = peerIDData else {
                assertionFailure()
                break
            }
            sendData(data: data, of: peerUUIDCharacteristic, to: central, sendSize: false)
        case CBUUID.PeerInfoCharacteristicID:
            let data = NSKeyedArchiver.archivedData(withRootObject: NetworkPeerInfo(peer: UserPeerInfo.instance.peer))
            sendData(data: data, of: peerInfoCharacteristic, to: central, sendSize: true)
        case CBUUID.PortraitCharacteristicID:
            guard let data = try? Data(contentsOf: UserPeerInfo.instance.pictureResourceURL) else { return }
            sendData(data: data, of: portraitCharacteristic, to: central, sendSize: true)
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
        interruptedTransfers.removeAll() // TEST does this keep the elements in transfers?
        for (data, characteristic, central, sendSize) in transfers {
            sendData(data: data, of: characteristic, to: central, sendSize: sendSize)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == peerUUIDCharacteristic.uuid {
            request.value = peerIDData
            if request.value != nil {
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .unlikelyError)
            }
        } else {
            peripheral.respond(to: request, withResult: .readNotPermitted)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        var error: CBATTError.Code = .success
        var _peer: (PeerID, CBCentral)? = nil
        var _pin: (PeerID, Bool)? = nil
        for request in requests {
            if request.characteristic.uuid == peerUUIDCharacteristic.uuid {
                guard let data = request.value else { continue }
                guard let peerID = PeerID(data: data) else {
                    error = .unlikelyError
                    break
                }
                _peer = (peerID, request.central)
            } else if request.characteristic.uuid == pinnedCharacteristic.uuid {
                guard let data = request.value else {
                    error = .unlikelyError
                    break
                }
                guard let pinFlag = data.first else {
                    error = .unlikelyError
                    break
                }
                guard let peerID = _availableCentrals[request.central] else {
                    error = .unlikelyError
                    break
                }
                _pin = (peerID, pinFlag != 0)
            } else {
                error = .writeNotPermitted
                break
            }
        }
        if error == .success {
            if let peer = _peer {
                _availableCentrals[peer.1] = peer.0
            }
            if let pin = _pin {
                if pin.1 {
                    delegate?.receivedPin(from: pin.0)
                }
            }
        }
        peripheral.respond(to: requests.first!, withResult: error)
    }
    
    // MARK: Private Methods
    
    private func sendData(data: Data, of characteristic: CBMutableCharacteristic, to central: CBCentral, sendSize: Bool) {
        if sendSize {
            // send the amount of bytes in data in the first package
            var size = Int32(data.count)
            let sizePointer = withUnsafeMutablePointer(to: &size, { (pointer) -> UnsafeMutablePointer<Int32> in
                return pointer
            })
            
            let sizeData = Data(bytesNoCopy: sizePointer, count: 4, deallocator: Data.Deallocator.none)
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
