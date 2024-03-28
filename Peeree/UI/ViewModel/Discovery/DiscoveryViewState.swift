//
//  DiscoveryViewState.swift
//  Peeree
//
//  Created by Christopher Kobusch on 14.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import Foundation

import PeereeCore
import PeereeDiscovery

import KeychainWrapper

// Global UI state.
@MainActor
class DiscoveryViewState: ObservableObject, DiscoveryViewModelDelegate {

	/// Discovery personas must have a PeereeIdentity, which requires a public key next to the PeerID.
	typealias RequiredData = PeerInfo

	// MARK: Static Constants

	static let MaxRememberedHours = 24

	/// Global state object.
	static let shared = DiscoveryViewState()

	// MARK: Variables

	/// Whether the main / browse view is in front.
	var browsing = false

	/// The `PeeringController.peering` state for the main thread.
	@Published var peering: Bool = false

	/// The last known state of the Bluetooth network.
	@Published var isBluetoothOn = false

	/// Whether all data is loaded from disk.
	@Published private(set) var isLoaded = false

	@Published var profile = Profile()

	/// Filter for peers.
	@Published var browseFilter = BrowseFilter() {
		didSet {
			filterChanged()
		}
	}

	/// Sorted list of relevant people nearby.
	@Published private(set) var peopleInFilter: [DiscoveryPerson] = []

	/// Sorted list of filtered-out people nearby.
	@Published private(set) var peopleOutFilter: [DiscoveryPerson] = []

	/// Display this peer in an overlay.
	@Published var displayedPersona: DiscoveryPerson? = nil

	/// All encountered people.
	private (set) var people: [PeerID : DiscoveryPerson] = [:]

	// MARK: Methods

	func load() async throws {
		guard !isLoaded else { return }

		defer {
			// We act like we loaded the data even if an error occured to allow for recovery (under data loss).
			isLoaded = true
		}

		try await profile.load()

		browseFilter = try await BrowseFilter.load()
	}

	func calculateViewLists() {
		peopleInFilter.removeAll()
		peopleOutFilter.removeAll()

		let now = Date()
		let cal = Calendar.current as NSCalendar

		for p in people.values {
			self.insertIntoViewList(person: p, calendar: cal, now: now)
		}
	}

	func addPersona(of peerID: PeerID, with data: PeerInfo) -> DiscoveryPerson {
		// This lets us control the instances of DiscoveryPerson.

		let ret: DiscoveryPerson
		if let persona = people[peerID] {
			persona.info = data

			ret = persona
		} else {
			ret = DiscoveryPerson(peerID: peerID, info: data, lastSeen: Date.distantPast)
			people[peerID] = ret

			insertIntoViewList(person: ret)
		}

		return ret
	}

	// Retrieve a person.
	func persona(of peerID: PeerID) -> DiscoveryPerson {
		return people[peerID, default: DiscoveryPerson(peerID: peerID, info: PeerInfo(nickname: peerID.uuidString, gender: .queer, age: nil, hasPicture: false), lastSeen: Date.distantPast)]
	}

	/// Removes the view model of `peerID`.
	public func removePersona(of peerID: PeerID) {
		people.removeValue(forKey: peerID)
		peopleInFilter.removeAll { $0.peerID == peerID }
		peopleOutFilter.removeAll { $0.peerID == peerID }
	}

	/// Removes all view models.
	public func clear() {
		people.removeAll()
		peopleInFilter.removeAll()
		peopleOutFilter.removeAll()
	}

	// MARK: Private

	// Log tag.
	private static let LogTag = "DiscoveryViewState"

	private func insertIntoViewList(person: DiscoveryPerson, calendar: NSCalendar = Calendar.current as NSCalendar, now: Date = Date()) {
		// make sure that Profile.person.lastSeen is Date.distantFuture!
		let lastSeenAgoCalc = calendar.components(NSCalendar.Unit.hour, from: person.lastSeen, to: now, options: []).hour
		let lastSeenAgo = lastSeenAgoCalc ?? Self.MaxRememberedHours + 1

		guard lastSeenAgo < Self.MaxRememberedHours else { return }

		browseFilter.check(info: person.info, pinState: .unpinned) ? peopleInFilter.append(person) : peopleOutFilter.append(person)

		// TODO: inefficient
		peopleInFilter.sort { p1, p2 in
			p1.lastSeen.timeIntervalSince1970 < p2.lastSeen.timeIntervalSince1970
		}
		peopleOutFilter.sort { p1, p2 in
			p1.lastSeen.timeIntervalSince1970 < p2.lastSeen.timeIntervalSince1970
		}
	}

	/// Persists this filter.
	private func filterChanged() {
		Task {
			try await self.browseFilter.save()
		}

		calculateViewLists()
	}
}
