//
//  BrowseFilter.swift
//  Peeree
//
//  Created by Christopher Kobusch on 13.09.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

/// Encapsulates values on which the remote peers are filtered before they are presented to the user.
struct BrowseFilter: Codable {
	/// Key in `UserDefaults`.
	private static let PrefKey = "BrowseFilter"

	/// Retrieves the stored filter from `UserDefaults`.
	public static func getFilter() throws -> BrowseFilter {
		return try unarchiveFromUserDefs(BrowseFilter.self, PrefKey) ?? BrowseFilter()
	}

	/// Names of notifications sent by ``BrowseFilter``.
	enum NotificationName: String {
		/// The persisted filter changed; the sending object is the persisted ``BrowseFilter``.
		case filterChanged
	}

	/// Only notify about specific genders.
	struct GenderFilter: OptionSet, Codable {
		let rawValue: Int

		/// Include females.
		static let females	= GenderFilter(rawValue: 1 << 0)

		/// Include males.
		static let males	= GenderFilter(rawValue: 1 << 1)

		/// Include queers.
		static let queers	= GenderFilter(rawValue: 1 << 2)

		/// Include all genders.
		static let all: GenderFilter = [.females, .males, .queers]
	}
	
	/// Minimum age to be included; range from 18..100.
	var ageMin: Float = 18.0

	/// Maximum age to be included; range from 10..100 or 0, where 0 means ∞.
	var ageMax: Float = 0.0

	/// Genders to be included.
	var gender: GenderFilter = GenderFilter.all

	/// Include only people who have an age set.
	var onlyWithAge: Bool = false

	/// Include only people who have configured a portrait picture.
	var onlyWithPicture: Bool = false

	/// Persists this filter.
	func writeToDefaults() throws {
		try archiveInUserDefs(self, forKey: BrowseFilter.PrefKey)
		NotificationName.filterChanged.postAsNotification(object: self)
	}

	/// Applies this filter and returns whether it fits.
	func check(info: PeerInfo, pinState: PinState) -> Bool {
		// always keep matched peers in filter
		guard pinState != .pinMatch else { return true }

		let matchingGender = (gender.contains(.females) && info.gender == .female) ||
			(gender.contains(.males) && info.gender == .male) ||
			(gender.contains(.queers) && info.gender == .queer)

		var matchingAge: Bool
		if let peerAge = info.age {
			matchingAge = ageMin <= Float(peerAge) && (ageMax == 0.0 || ageMax >= Float(peerAge))
		} else {
			matchingAge = true
		}

		let hasRequiredProperties = (!onlyWithPicture || info.hasPicture) && (!onlyWithAge || info.age != nil)

		return matchingAge && matchingGender && hasRequiredProperties
	}
}
