//
//  SocialViewDelegate.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import PeereeCore

/// Handles interaction with the social view module.
protocol SocialViewDelegate {
	func createIdentity()

	func deleteIdentity()

	func pinToggle(peerID: PeerID)

	func removePin(peerID: PeerID)

	func reportPortrait(peerID: PeerID)
}
