//
//  PeerDiscoveryState.swift
//  PeereeDiscovery
//
//  Created by Christopher Kobusch on 22.06.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth

import PeereeCore
import KeychainWrapper

/// Information available after a peer was initially discovered.
struct Discovered {
	/// The advertised last changed date of the remote peer.
	let lastChanged: Date
}

/// Information available after a peer's identity was verified.
struct Identified {
	/// The public key of the remote peer.
	let publicKey: AsymmetricPublicKey

	/// The advertised last changed date of the remote peer.
	let lastChanged: Date
}

/// Denotes the state of the discovery process.
enum PeerDiscoveryState {
	/// Advertised PeerID and last-changed date retrieved.
	case discovered(Date)

	/// Peeree Identity verified.
	case identified(Identified)

	/// Peer Info retrieved.
	case queried(Identified)

	/// Downloading additional information.
	case scraping(Identified)

	/// All available info retrieved.
	case finished(Identified)
}
