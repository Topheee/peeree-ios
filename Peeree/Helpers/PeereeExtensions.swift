//
//  PeereeExtensions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 05.08.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth

extension CBPeripheral {
    var peereeService: CBService? {
        return services?.first { $0.uuid == CBUUID.PeereeServiceID }
    }
    
    func readValues(for characteristics: [CBCharacteristic]) {
        for characteristic in characteristics {
            if characteristic.properties.contains(.read) {
                readValue(for: characteristic)
            } else {
                NSLog("Attempt to read unreadable characteristic \(characteristic.uuid.uuidString)")
            }
        }
    }
}

extension CBService {
    func getCharacteristics(withIDs characteristicIDs: [CBUUID]) -> [CBCharacteristic]? {
        return characteristics?.filter { characteristic in characteristicIDs.contains(characteristic.uuid) }
    }
}

extension RawRepresentable where Self.RawValue == String {
    func postAsNotification(object: Any?, userInfo: [AnyHashable : Any]? = nil) {
        NotificationCenter.default.post(name: Notification.Name(rawValue: self.rawValue), object: object, userInfo: userInfo)
    }
    
    public func addPeerObserver(peerIDKey: String = "peerID", usingBlock block: @escaping (PeerID, Notification) -> Void) -> NSObjectProtocol {
        return NotificationCenter.addObserverOnMain(self.rawValue) { (notification) in
            if let peerID = notification.userInfo?[peerIDKey] as? PeerID {
                block(peerID, notification)
            }
        }
    }
    public func addPeerObserver(for observedPeerID: PeerID, peerIDKey: String = "peerID", usingBlock block: @escaping (PeerID, Notification) -> Void) -> NSObjectProtocol {
        return NotificationCenter.addObserverOnMain(self.rawValue) { (notification) in
            if let peerID = notification.userInfo?[peerIDKey] as? PeerID, observedPeerID == peerID {
                block(peerID, notification)
            }
        }
    }
}
