//
//  DiscoveryExtensions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.04.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth
import PeereeCore

extension CBPeripheral {
	/// The `CBService` with the Peeree UUID, if available.
	var peereeService: CBService? {
		return services?.first { $0.uuid == CBUUID.PeereeServiceID }
	}
}

extension CBService {
	/// Retrieves the `CBCharacteristic` with `uuid` equal to `id` from `characteristics`.
	func get(characteristic id: CBUUID) -> CBCharacteristic? {
		return characteristics?.first { $0.uuid == id }
	}

	/// Retrieves the `CBCharacteristic`s with `uuid` equal to `ids` from `characteristics`.
	func get(characteristics ids: [CBUUID]) -> [CBCharacteristic]? {
		return characteristics?.filter { characteristic in ids.contains(characteristic.uuid) }
	}
}

extension CBCharacteristic {
	/// Size of the first packet of 'split' characteristics (containing the amount of bytes for the following packets), i.e., characteristics transferred in multiple messages.
	typealias SplitCharacteristicSize = Int32
}

extension CBUUID {
	static let PeereeServiceID = CBUUID(string: "EEB9E7F2-5442-42CC-AC91-E25E10A8D6EE")
	// we cannot include the "pin match indication" process in the "remote auth" process, because we need to check with the server, in case we pinned but are not aware of a match -> attacker sees delay when we query the server
	static let PinMatchIndicationCharacteristicID = CBUUID(string: "05560D3E-2163-4705-AA6F-DED12918DCEE")
	static let LocalPeerIDCharacteristicID = CBUUID(string: "52FA3B9A-59E8-41AD-BEBE-19826589116A")
	static let RemoteUUIDCharacteristicID = CBUUID(string: "3C91DF5A-89E4-4F55-9CA2-0CF9E5EABC5D")
	static let LastChangedCharacteristicID = CBUUID(string: "6F443A3C-F799-4DC1-A02A-72F2D8EA8B24")
	static let AggregateCharacteristicID = CBUUID(string: "4E0E2DB5-37E1-4083-9463-1AAECABF9179")
	static let NicknameCharacteristicID = CBUUID(string: "AC5971AF-CB30-4ABF-A699-F13C8E286A91")
	static let PortraitCharacteristicID = CBUUID(string: "DCB9A435-2795-4D6A-BE5D-854CE1EA8890")
	static let PublicKeyCharacteristicID = CBUUID(string: "2EC65417-7DE7-459B-A9CC-67AD01842A4F")
	static let AuthenticationCharacteristicID = CBUUID(string: "79427315-3071-4EA1-AD76-3FF04FCD51CF")
	static let RemoteAuthenticationCharacteristicID = CBUUID(string: "21AA8B5C-34E7-4694-B3E6-8F51A79811F3")
	static let ConnectBackCharacteristicID = CBUUID(string: "D14F4899-CF39-4F26-8C3E-E81FA3803393")
	static let BiographyCharacteristicID = CBUUID(string: "08EC3C63-CB96-466B-A591-40F8E214BE74")

	static let PeerIDSignatureCharacteristicID = CBUUID(string: "D05A4FA4-F203-4A76-A6EA-560152AD74A5")
	static let AggregateSignatureCharacteristicID = CBUUID(string: "17B23EC4-F543-48C6-A8B8-F806FE035F10")
	static let NicknameSignatureCharacteristicID = CBUUID(string: "B69EB678-ABAC-4134-828D-D79868A6CB4A")
	static let PortraitSignatureCharacteristicID = CBUUID(string: "44BFB98E-56AB-4436-9F14-7277C5D6A8CA")
	static let BiographySignatureCharacteristicID = CBUUID(string: "1198D287-23DD-4F8A-8F08-0EB6B77FBF29")
}
