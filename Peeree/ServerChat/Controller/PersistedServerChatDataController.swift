//
//  PersistedServerChatDataController.swift
//  PeereeServerChat
//
//  Created by Christopher Kobusch on 01.05.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import Foundation
import PeereeCore

/// Controller for disk-operations involving server chat data.
actor PersistedServerChatDataController {
	// MARK: - Public and Internal

	/// Create an instance of `PersistedServerChatDataController`.
	public init(filename: String) {
		self.filename = filename
	}

	// MARK: Methods

	/// Removes all associated data of a `PeerID` from disk.
	public func removePeerData(_ peerIDs: Set<PeerID>) throws {
		for peerID in peerIDs {
			self.persistedLastReads.removeValue(forKey: peerID)
		}

		try self.saveLastReads()
	}

	/// Wipes all data from disk.
	public func clear() {
		try? FileManager.default.deleteFile(at: self.lastReadsURL)
		self.persistedLastReads = [:]
	}

	/// Read-only access to persisted last read dates.
	public var lastReads: [PeerID : Date] {
		return self.persistedLastReads
	}

	/// Persists persisted last read date of `peerID`.
	public func set(lastRead date: Date, of peerID: PeerID) throws {
		self.persistedLastReads[peerID] = date
		try self.saveLastReads()
	}

	/// Retrieves all necessary data from disk. You should call this method as soon as possible after creating the `PersistedPeersController`.
	public func loadInitialData() throws {
		try self.loadLastReads()
	}

	// MARK: - Private

	// MARK: Constants

	/// Base file name for all files created by an instance of this class.
	private let filename: String

	// MARK: Variables

	/// Locator of file containing all last read dates; thread-safe.
	private var lastReadsURL: URL {
		// Create a file path to our documents directory
		let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
		return URL(fileURLWithPath: paths[0]).appendingPathComponent("\(filename).lastReadEventIDs.json", isDirectory: false)
	}

	/// All persisted last read dates; must be accessed on targetQueue.
	private var persistedLastReads = [PeerID : Date]()

	/// Retrieves all persisted last read dates from disk; call from `persistenceQueue` only.
	private func loadLastReads() throws {
		guard let data = FileManager.default.contents(atPath: self.lastReadsURL.path) else { return }

		let decoder = JSONDecoder()
		let decodedLastReads = try decoder.decode([PeerID : Date].self, from: data)
		self.persistedLastReads = decodedLastReads
	}

	/// Perists all last read dates on disk; must be accessed on targetQueue.
	private func saveLastReads() throws {
		try save(persistedLastReads, at: lastReadsURL)
	}

	/// Persists an `Encodable` `Collection` at `url`.
	private func save<EncodableCollection: Encodable>(_ save: EncodableCollection, at url: URL) throws where EncodableCollection: Collection {
		if save.isEmpty {
			try FileManager.default.deleteFile(at: url)
		} else {
			let jsonData = try JSONEncoder().encode(save)
			if !FileManager.default.createFile(atPath: url.path, contents: jsonData, attributes: nil) {
				throw createApplicationError(localizedDescription: "could not create file \(url.path)")
			}
		}
	}
}
