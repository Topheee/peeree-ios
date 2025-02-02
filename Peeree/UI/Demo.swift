//
//  Demo.swift
//  Peeree
//
//  Created by Christopher Kobusch on 08.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeCore
import PeereeDiscovery
import PeereeIdP
import PeereeSocial

//fileprivate let SamplePublicKeyData = Data(hexString: "040248b9c0a2d23086eba6d55671ac9c440f853760bfd909ad0fb1b3249f6b2cb15aa052362bb8d5650a024d800060f1f0de4077f29444f7051769af29e762967b")!
//
//extension PeereeIdentity {
//	static func demo(_ peerID: PeerID? = nil) -> PeereeIdentity {
//		return try! PeereeIdentity(peerID: peerID ?? PeerID(), publicKeyData: SamplePublicKeyData)
//	}
//}

extension SocialViewState {
	@discardableResult
	func demo(_ peerID: PeerID? = nil) -> SocialPerson {
		var rng = SystemRandomNumberGenerator()
		let r = abs(Int(truncatingIfNeeded: rng.next()))
		return addPersona(of: peerID ?? PeerID(), with: PinState.allCases[r % PinState.allCases.count])
	}
}


extension ServerChatViewState {
	func demo(_ peerID: PeerID? = nil) -> ServerChatPerson {
		return persona(of: peerID ?? PeerID())
	}
}


extension DiscoveryViewState {
	private static let names = ["Anna", "Lia", "Teresa", "Lisa", "Petra", "Sina"]

	private static let pictureNames = ["p1", "p2", "p3"]

	@discardableResult
	func demo(_ peerID: PeerID? = nil) -> DiscoveryPerson {
		var rng = SystemRandomNumberGenerator()
		let r = abs(Int(truncatingIfNeeded: rng.next()))
		var age: Int? = r % PeerInfo.MaxAge
		if age! < PeerInfo.MinAge { age = nil }
		let info = PeerInfo(nickname: Self.names[r % Self.names.count], gender: PeerInfo.Gender.allCases[r % PeerInfo.Gender.allCases.count], age: age, hasPicture: true)
		let discoveryPersona = addPersona(of: peerID ?? PeerID(), with: info)
		discoveryPersona.set(portrait: UIImage(named: Self.pictureNames[r % Self.pictureNames.count])?.cgImage, hash: Data())
		discoveryPersona.lastSeen = Date()
		return discoveryPersona
	}
}
