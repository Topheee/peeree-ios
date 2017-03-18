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
    static let PeereeServiceID = CBUUID(string: "EEB9E7F2-5442-42CC-AC91-E25E10A8D6EE")
    static let PortraitCharacteristicID = CBUUID(string: "DCB9A435-2795-4D6A-BE5D-854CE1EA8890")
    static let PinnedCharacteristicID = CBUUID(string: "05560D3E-2163-4705-AA6F-DED12918DCEE")
    static let UUIDCharacteristicID = CBUUID(string: "52FA3B9A-59E8-41AD-BEBE-19826589116A")
    static let PeerInfoServiceID = CBUUID(string: "B1A29886-5702-4959-B34F-A2F12AABF7F1")
    
    static let AggregateCharacteristicID = CBUUID(string: "4E0E2DB5-37E1-4083-9463-1AAECABF9179")
    static let LastChangedCharacteristicID = CBUUID(string: "6F443A3C-F799-4DC1-A02A-72F2D8EA8B24")
    static let NicknameCharacteristicID = CBUUID(string: "AC5971AF-CB30-4ABF-A699-F13C8E286A91")
    
    static let peereeCharacteristicIDs = [UUIDCharacteristicID, PortraitCharacteristicID, PinnedCharacteristicID]
    static let peerInfoCharacteristicIDs = [AggregateCharacteristicID, LastChangedCharacteristicID, NicknameCharacteristicID]
    static let splitCharacteristicIDs = [PortraitCharacteristicID]
}

class PeerManager: NSObject {
    private static let indicatedProperties: CBCharacteristicProperties = [.indicate]
    private static let indicatedWriteProperties: CBCharacteristicProperties = [.indicate, .write]
    private static let readProperties: CBCharacteristicProperties = [.read]
    private static let readWriteProperties: CBCharacteristicProperties = [.read, .write]
    
    private static let readPermissions: CBAttributePermissions = [.readable]
    private static let readWritePermissions: CBAttributePermissions = [.readable, .writeable]
    private static let indicateWritePermissions: CBAttributePermissions = [.writeable]
    
    static let uuidEncoding = String.Encoding.ascii
    static let nicknameEncoding = String.Encoding.utf8 // TODO UTF16 or whatever for internationalization?
    
    // value: UserPeerInfo.instance.peer.idData
    let peerUUIDCharacteristic = CBMutableCharacteristic(type: CBUUID.UUIDCharacteristicID, properties: PeerManager.readWriteProperties, value: nil, permissions: PeerManager.readWritePermissions)
    // value: Data(count: 1)
    let pinnedCharacteristic = CBMutableCharacteristic(type: CBUUID.PinnedCharacteristicID, properties: PeerManager.readWriteProperties.union(.writeWithoutResponse), value: nil, permissions: PeerManager.readWritePermissions)
    // value try? Data(contentsOf: UserPeerInfo.instance.pictureResourceURL)
    let portraitCharacteristic = CBMutableCharacteristic(type: CBUUID.PortraitCharacteristicID, properties: PeerManager.indicatedProperties, value: nil, permissions: [])
    let peereeService = CBMutableService(type: CBUUID.PeereeServiceID, primary: true)
    
    // value: aggregateData
    let aggregateCharacteristic = CBMutableCharacteristic(type: CBUUID.AggregateCharacteristicID, properties: PeerManager.readProperties, value: UserPeerInfo.instance.peer.aggregateData, permissions: PeerManager.readPermissions)
    // value: lastChangedData
    let lastChangedCharacteristic = CBMutableCharacteristic(type: CBUUID.LastChangedCharacteristicID, properties: PeerManager.readProperties, value: UserPeerInfo.instance.peer.lastChangedData, permissions: PeerManager.readPermissions)
    // value nicknameData
    let nicknameCharacteristic = CBMutableCharacteristic(type: CBUUID.NicknameCharacteristicID, properties: PeerManager.readProperties, value: UserPeerInfo.instance.peer.nicknameData, permissions: PeerManager.readPermissions)
    let peerInfoService = CBMutableService(type: CBUUID.PeerInfoServiceID, primary: false)
    
    func pinnedData(_ pinned: Bool) -> Data {
        return pinned ? Data(repeating: UInt8(1), count: 1) : Data(count: 1)
    }
    
    override init() {
        peereeService.characteristics = [peerUUIDCharacteristic, pinnedCharacteristic, portraitCharacteristic]
        peerInfoService.characteristics = [aggregateCharacteristic, lastChangedCharacteristic, nicknameCharacteristic]
        peereeService.includedServices = [peerInfoService]
    }
}
