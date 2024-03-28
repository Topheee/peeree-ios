//
//  RemoteState.swift
//  PeereeCore
//
//  Created by Christopher Kobusch on 28.03.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

/// A state stored on a remote server.
public protocol RemoteState {
	/// We requested a state change and have not yet got confirmation.
	var isTransitioning: Bool { get }
}

extension RemoteState {
	/// We are not aware of any in-flight state change operations.
	var isFixed: Bool { return !isTransitioning }
}

public enum RemoteToggle {
	case on, turningOff, off, turningOn
}

extension RemoteToggle: RemoteState {
	public var isTransitioning: Bool {
		return self == .turningOn || self == .turningOff
	}
}
