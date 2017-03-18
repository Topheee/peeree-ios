//
//  PeereeExtensions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 05.08.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth

extension PeerID {
    var displayName: String {
        return self == UserPeerInfo.instance.peer.peerID ? UserPeerInfo.instance.peer.nickname : PeeringController.shared.remote.getPeerInfo(of: self)?.nickname ?? NSLocalizedString("New Peer", comment: "Heading of Person View when peer information is not yet retrieved.")
    }
}

extension CBPeripheral {
    var peereeService: CBService? {
        return services?.first
    }
    
    var peerInfoService: CBService? {
        return peereeService?.includedServices?.first
    }
    
    func readValues(for characteristics: [CBCharacteristic]) {
        for characteristic in characteristics {
            readValue(for: characteristic)
        }
    }
}
