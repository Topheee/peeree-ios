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
    func sessionHandlerDidPin(_ peerID: PeerID)
    func isPinned(_ peerID: PeerID) -> Bool
}

/// The LocalPeerManager singleton serves as an globally access point for information about the local peer, the user's information
final class LocalPeerManager: PeerManager, LocalPeering, CBPeripheralManagerDelegate {
    private let dQueue = DispatchQueue(label: "com.peeree.localpeermanager_q", attributes: [])
    
    private var peripheralManager: CBPeripheralManager! = nil
    
    private var interruptedTransfers: [(Data, CBMutableCharacteristic, CBCentral)] = []
    
    private var _availableCentrals = SynchronizedDictionary<PeerID, CBCentral>()
    
    var availablePeers: [PeerID] {
        return _availableCentrals.accessQueue.sync {
            _availableCentrals.dictionary.flatMap({ (peerID, _) -> PeerID? in
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
        
        // TODO cancel connections
        peripheralManager.stopAdvertising()
        peripheralManager = nil
        delegate?.advertisingStopped()
    }
    
    func pin(_ peerID: PeerID) {
        guard let central = self._availableCentrals[peerID] else {
            // TODO confirmation.revoke
            return
        }
        let data = pinnedData(for: peerID)
        let characteristic = self.pinnedCharacteristic
        if peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: [central]) {
            delegate?.sessionHandlerDidPin(peerID)
        } else {
            interruptedTransfers.append((data, characteristic, central))
        }
    }
    
    func isPinning(_ peerID: PeerID) -> Bool {
        return interruptedTransfers.contains(where: { (_, _, central) -> Bool in
            return central.identifier == peerID
        })
    }
    
    // MARK: CBPeripheralManagerDelegate
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            NSLog("Adding service \(service) failed (\(error!.localizedDescription)).")
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
            peripheralManager = nil
            delegate?.advertisingStopped()
        case .poweredOff:
            peripheralManager = nil
            delegate?.advertisingStopped()
        case .poweredOn:
            UserPeerInfo.instance.iBeaconUUID = UUID()
            peripheralManager.add(peripheralService)
            peripheralManager.startAdvertising(nil)
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard let theError = error else {
            delegate?.advertisingStarted()
            return
        }
        
        delegate?.advertisingStopped()
        NSLog("Failed to start advertising. (\(theError.localizedDescription))")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        NSLog("Central subscribed to characteristic")
        switch characteristic.uuid {
        case CBUUID.UUIDCharacteristicID:
            guard let data = UserPeerInfo.instance.peer.peerID.uuidString.data(using: String.Encoding.ascii) else {
                assertionFailure()
                break
            }
            sendData(data: data, of: peerUUIDCharacteristic, to: central)
        case CBUUID.PeerInfoCharacteristicID:
            let data = NSKeyedArchiver.archivedData(withRootObject: NetworkPeerInfo(peer: UserPeerInfo.instance.peer))
            sendData(data: data, of: peerInfoCharacteristic, to: central)
        case CBUUID.PortraitCharacteristicID:
            guard let data = try? Data(contentsOf: UserPeerInfo.instance.pictureResourceURL) else { return }
            sendData(data: data, of: portraitCharacteristic, to: central)
        case CBUUID.PinnedCharacteristicID:
            sendData(data: pinnedData(for: central.identifier), of: portraitCharacteristic, to: central)
        default:
            break
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        NSLog("Central unsubscribed from characteristic")
        interruptedTransfers = interruptedTransfers.filter { (_, _, interruptedCentral) -> Bool in
            return interruptedCentral != central
        }
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        NSLog("Peripheral is ready to update subscribers")
        // Start sending again
        let transfers = interruptedTransfers
        interruptedTransfers.removeAll() // TODO does this keep the elements in transfers?
        for (data, characteristic, central) in transfers {
            sendData(data: data, of: characteristic, to: central)
        }
    }
    
    // MARK: Private Methods
    
    private func sendData(data: Data, of characteristic: CBMutableCharacteristic, to central: CBCentral) {
        // First up, check if we're meant to be sending an EOM
        var sendingEOM = data.count == 0
        
        if sendingEOM {
            
            // send it
            let didSend = peripheralManager.updateValue("EOM".data(using: String.Encoding.utf8)!, for:characteristic, onSubscribedCentrals:[central])
            
            // Did it send?
            if didSend {
                // It did, so mark it as sent
                sendingEOM = false
                NSLog("Sent: EOM")
            }
            
            // It didn't send, so we'll exit and wait for peripheralManagerIsReadyToUpdateSubscribers to call sendData again
            return;
        }
        
        // We're not sending an EOM, so we're sending data
        
        // Is there any left to send?
        var fromIndex = data.startIndex
        
        // There's data left, so send until the callback fails, or we're done.
        
        var didSend = true
        
        while didSend {
            // Make the next chunk
            
            let toIndex = data.index(fromIndex, offsetBy: central.maximumUpdateValueLength, limitedBy: data.endIndex) ?? data.endIndex
            //            // Work out how big it should be
            //            var amountToSend = data.count - sendDataIndex
            //
            //            // Can't be longer than 20 bytes
            //            if amountToSend > central.maximumUpdateValueLength {
            //                amountToSend = central.maximumUpdateValueLength
            //            }
            
            // Copy out the data we want
            let chunk = data.subdata(in: fromIndex..<toIndex)
            
            // Send it
            didSend = peripheralManager.updateValue(chunk, for: characteristic, onSubscribedCentrals: [central])
            
            // If it didn't work, drop out and wait for the callback
            guard didSend else {
                interruptedTransfers.append((data.subdata(in: fromIndex..<data.endIndex), characteristic, central))
                return
            }
            
            // It did send, so update our index
            fromIndex = toIndex
            
            // Was it the last one?
            if fromIndex == data.endIndex {
                // It was - send an EOM
                
                // Set this so if the send fails, we'll send it next time
                sendingEOM = true
                
                // Send it
                guard peripheralManager.updateValue("EOM".data(using: String.Encoding.utf8)!, for: characteristic, onSubscribedCentrals: [central]) else { return }
                
                NSLog("Sent: EOM")
                
                return
            }
        }
    }
    
    private func pinnedData(for peerID: PeerID) -> Data {
        return (delegate?.isPinned(peerID) ?? false) ? Data(repeating: 1, count: 1) : Data(count: 1)
    }
}
