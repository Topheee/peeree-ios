//
//  DiscoveryPersonAspect.swift
//  PeereeDiscovery
//
//  Created by Christopher Kobusch on 15.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics

import PeereeCore

@MainActor
public protocol DiscoveryPersonAspect: PersonAspect {

	var info: PeerInfo { get set }

	var biography: String { get set }

	/// Last Bluetooth encounter.
	var lastSeen: Date { get set }

	var pictureProgress: Double { get set }

	func set(portrait: CGImage?, hash: Data)
}

