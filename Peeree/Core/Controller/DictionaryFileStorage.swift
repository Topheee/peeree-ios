//
//  DictionaryFileStorage.swift
//  Peeree
//
//  Created by Christopher Kobusch on 11.05.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

// Log tag.
private let LogTag = "DictionaryFileStorage"

/// Small wrapper around a dictionary that writes all changes to disk.
///
/// Typically, these attributes are small and thus the file can be read and
/// written in total.
// TODO: do we really need this? Do we really need to have a copy in RAM all the time?
public actor DictionaryFileStorage<D: Codable> {
	public let url: URL

	private(set) var storage = [PeerID : D]()

	public init(url: URL) {
		self.url = url
	}

	/// Loads all data from disk. Should be the first method called on an instance
	/// of this class.
	func load() throws {
		guard let data = self.fileManager.contents(atPath: self.url.path) else { return }

		let decoder = JSONDecoder()
		self.storage = try decoder.decode([PeerID : D].self, from: data)
	}

	/// Sets a new value for an attribute.
	public func set(_ attribute: D, for peerID: PeerID) throws {
		self.storage[peerID] = attribute
		try self.fileManager.save(self.storage, at: self.url)
	}

	/// Sets a new value for an attribute.
	public func removeAttribute(of peerID: PeerID) throws {
		self.storage.removeValue(forKey: peerID)
		try self.fileManager.save(self.storage, at: self.url)
	}

	// MARK: - Private

	// MARK: Constants

	private let fileManager = FileManager()
}
