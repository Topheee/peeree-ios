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

internal let LogTag = "PeereeDiscovery"

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
	private static let PeereeServiceUUID = UUID(uuidString: "EEB9E7F2-5442-42CC-AC91-E25E10A8D6EE")!
	// we cannot include the "pin match indication" process in the "remote auth" process, because we need to check with the server, in case we pinned but are not aware of a match -> attacker sees delay when we query the server
	private static let PinMatchIndicationCharacteristicUUID = UUID(uuidString: "05560D3E-2163-4705-AA6F-DED12918DCEE")!
	private static let OldLocalPeerIDCharacteristicUUID = UUID(uuidString: "52FA3B9A-59E8-41AD-BEBE-19826589116A")!
	private static let LocalPeerIDCharacteristicUUID = UUID(uuidString: "795D988B-AE8A-45B7-B3AC-3E7614B3929C")!
	private static let RemoteUUIDCharacteristicUUID = UUID(uuidString: "3C91DF5A-89E4-4F55-9CA2-0CF9E5EABC5D")!
	private static let LastChangedCharacteristicUUID = UUID(uuidString: "6F443A3C-F799-4DC1-A02A-72F2D8EA8B24")!
	private static let AggregateCharacteristicUUID = UUID(uuidString: "4E0E2DB5-37E1-4083-9463-1AAECABF9179")!
	private static let NicknameCharacteristicUUID = UUID(uuidString: "AC5971AF-CB30-4ABF-A699-F13C8E286A91")!
	private static let PortraitCharacteristicUUID = UUID(uuidString: "DCB9A435-2795-4D6A-BE5D-854CE1EA8890")!
	private static let PublicKeyCharacteristicUUID = UUID(uuidString: "2EC65417-7DE7-459B-A9CC-67AD01842A4F")!
	private static let AuthenticationCharacteristicUUID = UUID(uuidString: "79427315-3071-4EA1-AD76-3FF04FCD51CF")!
	private static let RemoteAuthenticationCharacteristicUUID = UUID(uuidString: "21AA8B5C-34E7-4694-B3E6-8F51A79811F3")!
	private static let ConnectBackCharacteristicUUID = UUID(uuidString: "D14F4899-CF39-4F26-8C3E-E81FA3803393")!
	private static let BiographyCharacteristicUUID = UUID(uuidString: "08EC3C63-CB96-466B-A591-40F8E214BE74")!
	private static let OldPeerIDSignatureCharacteristicUUID = UUID(uuidString: "D05A4FA4-F203-4A76-A6EA-560152AD74A5")!
	private static let PeerIDSignatureCharacteristicUUID = UUID(uuidString: "5346181F-9C52-4FC3-8052-1C7A4FB21CCE")!
	private static let AggregateSignatureCharacteristicUUID = UUID(uuidString: "17B23EC4-F543-48C6-A8B8-F806FE035F10")!
	private static let NicknameSignatureCharacteristicUUID = UUID(uuidString: "B69EB678-ABAC-4134-828D-D79868A6CB4A")!
	private static let PortraitSignatureCharacteristicUUID = UUID(uuidString: "44BFB98E-56AB-4436-9F14-7277C5D6A8CA")!
	private static let BiographySignatureCharacteristicUUID = UUID(uuidString: "1198D287-23DD-4F8A-8F08-0EB6B77FBF29")!
	private static let IdentityTokenCharacteristicUUID = UUID(uuidString: "02CDB809-9FC4-4F30-9C46-DD6E7B2A1808")!


	static var PinMatchIndicationCharacteristicID: CBUUID { CBUUID(nsuuid: PinMatchIndicationCharacteristicUUID) }
	static var OldLocalPeerIDCharacteristicID: CBUUID { CBUUID(nsuuid: OldLocalPeerIDCharacteristicUUID) }
	static var LocalPeerIDCharacteristicID: CBUUID { CBUUID(nsuuid: LocalPeerIDCharacteristicUUID) }
	static var RemoteUUIDCharacteristicID: CBUUID { CBUUID(nsuuid: RemoteUUIDCharacteristicUUID) }
	static var LastChangedCharacteristicID: CBUUID { CBUUID(nsuuid: LastChangedCharacteristicUUID) }
	static var AggregateCharacteristicID: CBUUID { CBUUID(nsuuid: AggregateCharacteristicUUID) }
	static var NicknameCharacteristicID: CBUUID { CBUUID(nsuuid: NicknameCharacteristicUUID) }
	static var PortraitCharacteristicID: CBUUID { CBUUID(nsuuid: PortraitCharacteristicUUID) }
	static var PublicKeyCharacteristicID: CBUUID { CBUUID(nsuuid: PublicKeyCharacteristicUUID) }
	static var AuthenticationCharacteristicID: CBUUID { CBUUID(nsuuid: AuthenticationCharacteristicUUID) }
	static var RemoteAuthenticationCharacteristicID: CBUUID { CBUUID(nsuuid: RemoteAuthenticationCharacteristicUUID) }
	static var ConnectBackCharacteristicID: CBUUID { CBUUID(nsuuid: ConnectBackCharacteristicUUID) }
	static var BiographyCharacteristicID: CBUUID { CBUUID(nsuuid: BiographyCharacteristicUUID) }

	static var OldPeerIDSignatureCharacteristicID: CBUUID { CBUUID(nsuuid: OldPeerIDSignatureCharacteristicUUID) }
	static var PeerIDSignatureCharacteristicID: CBUUID { CBUUID(nsuuid: PeerIDSignatureCharacteristicUUID) }
	static var AggregateSignatureCharacteristicID: CBUUID { CBUUID(nsuuid: AggregateSignatureCharacteristicUUID) }
	static var NicknameSignatureCharacteristicID: CBUUID { CBUUID(nsuuid: NicknameSignatureCharacteristicUUID) }
	static var PortraitSignatureCharacteristicID: CBUUID { CBUUID(nsuuid: PortraitSignatureCharacteristicUUID) }
	static var BiographySignatureCharacteristicID: CBUUID { CBUUID(nsuuid: BiographySignatureCharacteristicUUID) }
	static var IdentityTokenCharacteristicID: CBUUID { CBUUID(nsuuid: IdentityTokenCharacteristicUUID) }

	static var PeereeServiceID: CBUUID { CBUUID(nsuuid: PeereeServiceUUID) }
}
