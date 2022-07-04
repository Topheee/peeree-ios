//
//  PeereeIdentityViewModel.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.04.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation

/// The states a pin on a peer can be in.
public enum PinState {
	/// Pin process state machine states.
	case unpinned, pinning, pinned, unpinning, pinMatch

	/// Checks whether we have a pin match, are currently unpinning (but effectively still having a pin) or simply have an (unmatched) pin.
	var isPinned: Bool { return self == .pinned || self == .pinMatch || self == .unpinning }
}

/// Objectionable content classification requirement from App Store.
public enum ContentClassification {
	case objectionable, pending, none
}

/// View model of a specific `PeereeIdentity`.
public struct PeereeIdentityViewModel {

	/// The notifications sent by `PeereeIdentityViewModel`.
	public enum NotificationName: String {
		/// The `pinState` property was updated.
		case pinStateUpdated
	}

	/// The PeereeIdentity of this peer.
	public let id: PeereeIdentity

	/// The PeerID of this peer.
	public var peerID: PeerID { return id.peerID }

	/// Whether we are currently trying to pin this peer.
	public var pinState: PinState = .unpinned {
		didSet {
			NotificationName.pinStateUpdated.post(for: id.peerID)
		}
	}
}
