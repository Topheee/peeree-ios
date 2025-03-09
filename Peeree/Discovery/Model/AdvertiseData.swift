//
//  AdvertiseData.swift
//  Peeree
//
//  Created by Christopher Kobusch on 08.02.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

// Internal Dependencies
import PeereeCore

// External Dependencies
import KeychainWrapper

/// Information necessary for advertising via Bluetooth.
public struct AdvertiseData: Sendable {
	/// Our user ID.
	let peerID: PeerID

	/// The ID token issued by the Peeree server, proving our identity.
	let identityToken: Data

	/// Our private key, s.t. we can sign incoming requests.
	let keyPair: KeyPair

	/// Our profile information.
	let peerInfo: PeerInfo

	/// Our text.
	let biography: String

	/// Where to find our portrait (if available).
	let pictureResourceURL: URL

	public init(
		peerID: PeerID,
		identityToken: Data,
		keyPair: KeyPair,
		peerInfo: PeerInfo,
		biography: String,
		pictureResourceURL: URL
	) {
		self.peerID = peerID
		self.identityToken = identityToken
		self.keyPair = keyPair
		self.peerInfo = peerInfo
		self.biography = biography
		self.pictureResourceURL = pictureResourceURL
	}
}
