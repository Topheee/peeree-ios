//
//  BrowseFilter.swift
//  PeereeDiscovery
//
//  Created by Christopher Kobusch on 21.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import Foundation

public struct BrowseFilter: Codable, Sendable {

	/// Only notify about specific genders.
	public struct GenderFilter: OptionSet, Codable, Hashable, Sendable {
		public let rawValue: Int

		/// Include females.
		public static let females	= GenderFilter(rawValue: 1 << 0)

		/// Include males.
		public static let males	= GenderFilter(rawValue: 1 << 1)

		/// Include queers.
		public static let queers	= GenderFilter(rawValue: 1 << 2)

		/// Include all genders.
		public static let all: GenderFilter = [.females, .males, .queers]

		public init(rawValue: Int) {
			self.rawValue = rawValue
		}
	}

	/// Minimum age to be included; range from 18..100.
	public var ageMin: Float = 18.0

	/// Maximum age to be included; range from 10..100 or 0, where 0 means ∞.
	public var ageMax: Float = 0.0

	/// Genders to be included.
	public var gender: GenderFilter = GenderFilter.all

	/// Include only people who have an age set.
	public var onlyWithAge: Bool = false

	/// Include only people who have configured a portrait picture.
	public var onlyWithPicture: Bool = false

	/// Show people despite them being out-of-filter.
	public var displayFilteredPeople: Bool = false

	public init() {}
}

// For SwiftUI
extension BrowseFilter {
	public var allowFemales: Bool {
		get { return gender.contains(.females) }
		set { if newValue { gender.insert(.females) } else { gender.remove(.females) } }
	}

	public var allowMales: Bool {
		get { return gender.contains(.males) }
		set { if newValue { gender.insert(.males) } else { gender.remove(.males) } }
	}

	public var allowQueers: Bool {
		get { return gender.contains(.queers) }
		set { if newValue { gender.insert(.queers) } else { gender.remove(.queers) } }
	}
}

extension BrowseFilter {

	private static func fileURL() throws -> URL {
		try FileManager.default.url(for: .documentDirectory,
									in: .userDomainMask,
									appropriateFor: nil,
									create: false)
			.appendingPathComponent(DataKey)
	}

	public static func load() async throws -> BrowseFilter {
		let task = Task<BrowseFilter, Error> {
			let fileURL = try Self.fileURL()

			guard let data = try? Data(contentsOf: fileURL) else {
				return BrowseFilter()
			}

			let filter = try JSONDecoder().decode(BrowseFilter.self, from: data)
			return filter
		}

		return try await task.value
	}

//	public mutating func load() async throws {
//		let task = Task<BrowseFilter, Error> {
//			let fileURL = try Self.fileURL()
//
//			guard let data = try? Data(contentsOf: fileURL) else {
//				return BrowseFilter()
//			}
//
//			let filter = try JSONDecoder().decode(BrowseFilter.self, from: data)
//			return filter
//		}
//
//		self = try await task.value
//	}

	public func save() async throws {
		let task = Task {
			let data = try JSONEncoder().encode(self)
			let outfile = try Self.fileURL()
			try data.write(to: outfile)
		}

		_ = try await task.value
	}

	/// Identifier for stored filter.
	private static let DataKey = "BrowseFilter"
}
