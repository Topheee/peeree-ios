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
        return PeeringController.shared.remote.getPeerInfo(of: self)?.nickname ?? NSLocalizedString("New Peer", comment: "Heading of Person View when peer information is not yet retrieved.")
    }
}

extension CBService {
    func correspondingCharacteristic(for characteristic: CBCharacteristic) -> CBCharacteristic? {
        guard self.characteristics != nil else { return nil }
        for discoveredCharacteristic in self.characteristics! {
            if discoveredCharacteristic.uuid == characteristic.uuid {
                return discoveredCharacteristic
            }
        }
        return nil
    }
}
