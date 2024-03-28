//
//  SocialViewState.swift
//  Peeree
//
//  Created by Christopher Kobusch on 16.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import Foundation

import KeychainWrapper

import PeereeCore
import PeereeServer

// Global UI state.
@MainActor
final class SocialViewState: SocialViewModelDelegate, ObservableObject {

	/// Social personas must have a `PinState`.
	typealias RequiredData = PinState

	/// Global state object.
	static let shared = SocialViewState()

	var delegate: SocialViewDelegate?

	/// All known people.
	private (set) var people: [PeerID : SocialPerson] = [:]

	/// The `PeerID` of the local user, if available.
	public var userPeerID: PeerID? = nil

	/// Whether the user has create a `PeereeIdentity`.
	public var accountExists: Bool { return userPeerID != nil }

	/// Hashes of known inappropriate photos.
	public var objectionableImageHashes = Set<Data>()

	/// Hashes and timestamps of inappropriate content reports.
	public var pendingObjectionableImageHashes = [Data : Date]()

	var userSocialPersona: SocialPerson {
		return SocialPerson(peerID: self.userPeerID ?? PeerID(), pinState: .pinned)
	}

	// MARK: Methods

	/// Add or update a person.
	@discardableResult
	public func addPersona(of peerID: PeerID, with pinState: PinState = .unpinned) -> SocialPerson {
		// This lets us control the instances of SocialPerson.

		let ret: SocialPerson
		if let persona = people[peerID] {
			//wlog(Self.LogTag, "Overwriting already existing discovery persona.")

			persona.pinState = pinState

			ret = persona
		} else {
			ret = SocialPerson(peerID: peerID, pinState: pinState)
			people[peerID] = ret
		}

		return ret
	}

	/// Makes modifications to the view model of `peerID`, or adds `insert`, if no model is available.
	public func upsert(peerID: PeerID, insert: @autoclosure () -> SocialPerson, modifier: (inout SocialPerson) -> ()) {
		modifier(&people[peerID, default: insert()])
	}

	/// Retrieves the view model of `peerID`; possibly filled with empty data.
	public func persona(of peerID: PeerID) -> SocialPerson {
		return people[peerID, default: SocialPerson(peerID: peerID)]
	}

	/// Removes the view model of `peerID`.
	public func removePersona(of peerID: PeerID) {
		people.removeValue(forKey: peerID)
	}

	/// Removes all view models.
	public func clear() {
		userPeerID = nil
		people.removeAll()
	}

	/// Retrieves whether the image represented by `imageHash` contains objectionable content to our knowledge.
	public func classify(imageHash: Data) -> ContentClassification {
		objectionableImageHashes.contains(imageHash) ? .objectionable : (pendingObjectionableImageHashes[imageHash] != nil ? .pending : .none)
	}

	// MARK: - Private

	// Log tag.
	private static let LogTag = "SocialPersonController"
}
