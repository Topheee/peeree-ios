//
//  DiscoveryViewModelDelegate.swift
//  PeereeDiscovery
//
//  Created by Christopher Kobusch on 14.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import Foundation

import KeychainWrapper

import PeereeCore

/// Interface between the discovery module and the UI.
@MainActor
public protocol DiscoveryViewModelDelegate:
	AnyObject, Sendable, PersonAspectState
	where Aspect:
		DiscoveryPersonAspect, RequiredData == PeerInfo {

	/// The `PeeringController.peering` state for the main thread.
	var peering: Bool { get set }

	/// The last known state of the Bluetooth network.
	var isBluetoothOn: Bool { get set }

	/// Update the last seen date.
	func updateLastSeen(of peerID: PeerID, lastSeen: Date)
}
