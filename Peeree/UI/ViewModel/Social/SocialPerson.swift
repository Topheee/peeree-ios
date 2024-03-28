//
//  SocialPerson.swift
//  Peeree
//
//  Created by Christopher Kobusch on 16.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeCore
import PeereeServer

public final class SocialPerson: ObservableObject {

	/// The PeerID identifying this view model.
	public let peerID: PeerID

	@Published
	public var pinState: PinState

	init(peerID: PeerID, pinState: PinState = .unpinned) {
		self.peerID = peerID
		self.pinState = pinState
	}
}

extension SocialPerson: SocialPersonAspect {}
