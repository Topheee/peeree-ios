//
//  SocialPersonData.swift
//  PeereeServer
//
//  Created by Christopher Kobusch on 21.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//


import PeereeCore

struct SocialPersonData: Sendable {
	let peerID : PeerID

	let pinState: PinState
}
