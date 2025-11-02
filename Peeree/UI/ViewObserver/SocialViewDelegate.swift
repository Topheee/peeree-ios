//
//  SocialViewDelegate.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import PeereeCore

/// Handles interaction with the social view module.
@MainActor
protocol SocialViewDelegate {
	/// User requested to restore a Peeree Identity.
	func restoreIdentity(using recoveryCode: String)

	/// User requested to create a new Peeree Identity.
	func createIdentity()

	/// User requested to delete the current Peeree Identity.
	func deleteIdentity()

	/// User requested to toggle pin state on `peerID`.
	func pinToggle(peerID: PeerID)

	/// User requested to remove the pin from `peerID`.
	func removePin(peerID: PeerID)

	/// User requested to report the portrait of `peerID`.
	func reportPortrait(peerID: PeerID)
}
