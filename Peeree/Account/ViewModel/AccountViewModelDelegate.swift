//
//  AccountViewModelDelegate.swift
//  Peeree
//
//  Created by Christopher Kobusch on 11.01.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

// Platform Dependencies
import Foundation

// Internal Dependencies
import PeereeCore

/// Interface between the social module and the UI.
@MainActor
public protocol AccountViewModelDelegate: AnyObject, Sendable {

	/// Our user ID.
	var userPeerID: PeerID? { get set }

	/// Whether we created an account or are about to do so.
	var accountExists: RemoteToggle { get set }
}

