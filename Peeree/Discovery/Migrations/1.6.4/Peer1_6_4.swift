//
//  Peer1_6_4.swift
//  Peeree
//
//  Created by Christopher Kobusch on 10.05.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

// Internal Dependencies
import PeereeCore

/// Model of `Peer` as it was in v1.6.4.
public struct Peer1_6_4: Sendable, Codable {
	// MARK: - Public and Internal

	/// Constructs a `Peer` with its properties.
	public init(id: PeereeIdentity1_6_4, info: PeerInfo) {
		self.id = id
		self.info = info
	}

	// MARK: Constants

	/// The PeereeIdentity of this peer.
	public let id: PeereeIdentity1_6_4

	// MARK: Variables

	/// The basic properties of a peer.
	public var info: PeerInfo
}

extension Peer1_6_4 {
	func modernized() -> Peer {
		Peer(
			id: PeereeIdentity(
				peerID: self.id.peerID, publicKeyData: self.id.publicKey.key),
			info: self.info)
	}
}
