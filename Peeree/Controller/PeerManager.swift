//
//  PeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth

public typealias PeerID = UUID

extension PeerID {
    init?(data: Data) {
        guard let string = String(data: data, encoding: PeerManager.uuidEncoding) else {
            assertionFailure()
            return nil
        }
        self.init(uuidString: string)
    }
}

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

extension CBCharacteristic {
    var isSizePrefixed: Bool {
        return self.uuid == CBUUID.PeerInfoCharacteristicID || self.uuid == CBUUID.PortraitCharacteristicID
    }
}

class PeerManager: NSObject {
    private static let indicatedProperties: CBCharacteristicProperties = [.indicate] // TODO use encrypted notify
    private static let indicatedWriteProperties: CBCharacteristicProperties = [.indicate, .write] // TODO use encrypted notify
    private static let readWriteProperties: CBCharacteristicProperties = [.read, .write] // TODO use encrypted notify
    
    private static let readWritePermissions: CBAttributePermissions = [.readable, .writeable] // TODO use encrypted notify
    private static let indicateWritePermissions: CBAttributePermissions = [.writeable] // TODO use encrypted notify
    
    static let uuidEncoding = String.Encoding.ascii
    
    // value: peerIDData (UserPeerInfo.instance.peer.peerID.uuidString.data(using: PeerManager.uuidEncoding))
    let peerUUIDCharacteristic = CBMutableCharacteristic(type: CBUUID.UUIDCharacteristicID, properties: PeerManager.readWriteProperties, value: nil, permissions: PeerManager.readWritePermissions) // TODO use encrypted option variants
    // value: NSKeyedArchiver.archivedData(withRootObject: NetworkPeerInfo(peer: UserPeerInfo.instance.peer))
    let peerInfoCharacteristic = CBMutableCharacteristic(type: CBUUID.PeerInfoCharacteristicID, properties: PeerManager.indicatedProperties, value: nil, permissions: []) // TODO use encrypted option variants
    // value: Data(count: 1)
    let pinnedCharacteristic = CBMutableCharacteristic(type: CBUUID.PinnedCharacteristicID, properties: PeerManager.readWriteProperties.union(.writeWithoutResponse), value: nil, permissions: PeerManager.readWritePermissions) // TODO use authenticatedSignedWrites additionally (I hope the combination of write and authenticatedSignedWrites makes it encrypted with response)
    // value try? Data(contentsOf: UserPeerInfo.instance.pictureResourceURL)
    let portraitCharacteristic = CBMutableCharacteristic(type: CBUUID.PortraitCharacteristicID, properties: PeerManager.indicatedProperties, value: nil, permissions: []) // TODO use encrypted option variants
    let peripheralService = CBMutableService(type: CBUUID.BluetoothServiceID, primary: true)
    
    var peerIDData: Data? {
        return UserPeerInfo.instance.peer.peerID.uuidString.data(using: PeerManager.uuidEncoding)
    }
    
    func pinnedData(_ pinned: Bool) -> Data {
        return pinned ? Data(repeating: UInt8(1), count: 1) : Data(count: 1)
    }
    
    override init() {
        peripheralService.characteristics = [peerUUIDCharacteristic, peerInfoCharacteristic, pinnedCharacteristic, portraitCharacteristic]
    }
}
