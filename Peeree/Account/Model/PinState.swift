//
//  PinState.swift
//  PeereeServer
//
//  Created by Christopher Kobusch on 16.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

/// The states a pin on a peer can be in.
public enum PinState {
	/// Pin process state machine states.
	case unpinned, pinning, pinned, pinMatch, unpinning
}

extension PinState: CaseIterable, Sendable {}

extension PinState {

	/// Checks whether we have a pin match, are currently unpinning (but effectively still having a pin) or simply have an (unmatched) pin.
	public var isPinned: Bool { return self == .pinned || self == .pinMatch || self == .unpinning }

	public var isTransitioning: Bool {
		return self == .pinning || self == .unpinning
	}

	public var isFixed: Bool {
		return !isTransitioning
	}

	public var isPinnedOrUnpinning: Bool {
		return self == .pinMatch || self == .pinned || self == .unpinning
	}

	public var isUnpinnedOrPinning: Bool {
		return !isPinnedOrUnpinning
	}

	// Put state machine into following state.
	public mutating func next() {
		switch self {
		case .unpinned:
			self = .pinning
		case .pinning:
			self = .pinned
		case .pinned:
			self = .pinMatch
		case .pinMatch:
			self = .unpinning
		case .unpinning:
			self = .unpinned
		}
	}
}
