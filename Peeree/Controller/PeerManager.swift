//
//  PeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth

typealias PeerID = UUID

extension CBUUID {
    static let BluetoothServiceID = CBUUID(string: "EEB9E7F2-5442-42CC-AC91-E25E10A8D6EE")
    static let PeerInfoCharacteristicID = CBUUID(string: "E25DE954-D218-4853-A97F-90C1CFAD81A3")
    static let PortraitCharacteristicID = CBUUID(string: "DCB9A435-2795-4D6A-BE5D-854CE1EA8890")
    static let PinnedCharacteristicID = CBUUID(string: "05560D3E-2163-4705-AA6F-DED12918DCEE")
    static let UUIDCharacteristicID = CBUUID(string: "52FA3B9A-59E8-41AD-BEBE-19826589116A")
    
    static let characteristicIDs = [UUIDCharacteristicID, PeerInfoCharacteristicID, PortraitCharacteristicID, PinnedCharacteristicID]
    
    var isCharacteristicID: Bool {
        return self == CBUUID.PeerInfoCharacteristicID || self == CBUUID.PortraitCharacteristicID || self == CBUUID.PinnedCharacteristicID
    }
}

class PeerManager: NSObject {
    private static let properties: CBCharacteristicProperties = [.notify]
    var peerUUIDCharacteristic: CBMutableCharacteristic {
        // value: NSKeyedArchiver.archivedData(withRootObject: UserPeerInfo.instance.peer.peerID)
        return CBMutableCharacteristic(type: CBUUID.UUIDCharacteristicID, properties: PeerManager.properties, value: nil, permissions: [.readable]) // TODO use encrypted option variants
    }
    var peerInfoCharacteristic: CBMutableCharacteristic {
        // value: NSKeyedArchiver.archivedData(withRootObject: NetworkPeerInfo(peer: UserPeerInfo.instance.peer))
        return CBMutableCharacteristic(type: CBUUID.PeerInfoCharacteristicID, properties: PeerManager.properties, value: nil, permissions: [.readable]) // TODO use encrypted option variants
    }
    var pinnedCharacteristic: CBMutableCharacteristic {
        // value: Data(count: 1)
        return CBMutableCharacteristic(type: CBUUID.PinnedCharacteristicID, properties: PeerManager.properties, value: nil, permissions: [.readable]) // TODO use encrypted option variants
    }
    var portraitCharacteristic: CBMutableCharacteristic {
//        let data = try? Data(contentsOf: UserPeerInfo.instance.pictureResourceURL)
        return CBMutableCharacteristic(type: CBUUID.PortraitCharacteristicID, properties: PeerManager.properties, value: nil, permissions: [.readable]) // TODO use encrypted option variants
    }
    var peripheralService: CBMutableService {
        let service = CBMutableService(type: CBUUID.BluetoothServiceID, primary: true)
        service.characteristics = [peerUUIDCharacteristic, peerInfoCharacteristic, pinnedCharacteristic, portraitCharacteristic]
        return service
    }
}
