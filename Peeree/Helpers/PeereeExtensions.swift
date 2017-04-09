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
            readValue(for: characteristic)
        }
    }
}

extension CBService {
    func getCharacteristics(withIDs characteristicIDs: [CBUUID]) -> [CBCharacteristic]? {
        return characteristics?.filter { characteristic in characteristicIDs.contains(characteristic.uuid) }
    }
}
