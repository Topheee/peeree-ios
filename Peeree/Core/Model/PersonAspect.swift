//
//  PersonAspect.swift
//  PeereeCore
//
//  Created by Christopher Kobusch on 14.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import Foundation

/// View model of a person in a Peeree module; its 'persona'.
public protocol PersonAspect: AnyObject, Identifiable, Hashable {
	/// The PeerID identifying this view model.
	var peerID: PeerID { get }
}

// Implements `Identifiable`.
extension PersonAspect {
	/// Same as `peerID`.
	public var id: PeerID { return peerID }
}

// Implements `Equatable`.
//public func == <T>(lhs: T, rhs: T) -> Bool where T: PersonAspect {
//	return lhs.id == rhs.id
//}

// Implements `Hashable`.
extension PersonAspect {
	public static func == (lhs: Self, rhs: Self) -> Bool {
		return lhs.id == rhs.id
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}

/// The single state object that holds all domain data for every person.
@MainActor
public protocol PersonAspectState: AnyObject {

	/// The module-domain data associated to the person.
	associatedtype Aspect: PersonAspect
	/// The minimum required information to create an `Aspect`.
	associatedtype RequiredData

	/// Single source of truth of domain data.
	var people: [PeerID : Aspect] { get }

	/// Register a new person.
	func addPersona(of peerID: PeerID, with data: RequiredData) -> Aspect

	/// Retrieve a person.
	func persona(of peerID: PeerID) -> Aspect

	/// Removes the view model of `peerID`.
	func removePersona(of peerID: PeerID)

	/// Removes all view models.
	func clear()
}

