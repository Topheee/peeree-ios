//
//  PeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth

extension PeerID {
    private static let uuidEncoding = String.Encoding.ascii
    init?(data: Data) {
        guard let string = String(data: data, encoding: PeerID.uuidEncoding) else {
            assertionFailure()
            return nil
        }
        self.init(uuidString: string)
    }
    
    func encode() -> Data {
        return self.uuidString.data(using: PeerID.uuidEncoding)!
    }
}

extension CBUUID {
    static let PeereeServiceID = CBUUID(string: "EEB9E7F2-5442-42CC-AC91-E25E10A8D6EE")
    static let PortraitCharacteristicID = CBUUID(string: "DCB9A435-2795-4D6A-BE5D-854CE1EA8890")
    static let PinMatchIndicationCharacteristicID = CBUUID(string: "05560D3E-2163-4705-AA6F-DED12918DCEE")
    static let LocalUUIDCharacteristicID = CBUUID(string: "52FA3B9A-59E8-41AD-BEBE-19826589116A")
    static let RemoteUUIDCharacteristicID = CBUUID(string: "3C91DF5A-89E4-4F55-9CA2-0CF9E5EABC5D")
    static let AggregateCharacteristicID = CBUUID(string: "4E0E2DB5-37E1-4083-9463-1AAECABF9179")
    static let LastChangedCharacteristicID = CBUUID(string: "6F443A3C-F799-4DC1-A02A-72F2D8EA8B24")
    static let NicknameCharacteristicID = CBUUID(string: "AC5971AF-CB30-4ABF-A699-F13C8E286A91")
    static let PublicKeyCharacteristicID = CBUUID(string: "2EC65417-7DE7-459B-A9CC-67AD01842A4F")
    static let AuthenticationCharacteristicID = CBUUID(string: "79427315-3071-4EA1-AD76-3FF04FCD51CF")
    
    static let PeereeCharacteristicIDs = [RemoteUUIDCharacteristicID, LocalUUIDCharacteristicID, PortraitCharacteristicID, PinMatchIndicationCharacteristicID, AggregateCharacteristicID, LastChangedCharacteristicID, NicknameCharacteristicID, PublicKeyCharacteristicID, AuthenticationCharacteristicID]
    static let SplitCharacteristicIDs = [PortraitCharacteristicID]
}

class PeerManager: NSObject {
    /// prefixed (first packet sent) to split characteristics, that is, characteristics transferred in multiple messages
    typealias SplitCharacteristicSize = Int32
    
    func pinnedData(_ pinned: Bool) -> Data {
        return pinned ? Data(repeating: UInt8(1), count: 1) : Data(count: 1)
    }
}
