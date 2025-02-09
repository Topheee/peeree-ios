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
	let peerID: PeerID
	let keyPair: KeyPair
	let peerInfo: PeerInfo
	let biography: String
	let pictureResourceURL: URL

	public init(
		peerID: PeerID,
		keyPair: KeyPair,
		peerInfo: PeerInfo,
		biography: String,
		pictureResourceURL: URL
	) {
		self.peerID = peerID
		self.keyPair = keyPair
		self.peerInfo = peerInfo
		self.biography = biography
		self.pictureResourceURL = pictureResourceURL
	}
}
