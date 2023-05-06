//
//  PersistedServerChatDataController.swift
//  PeereeServerChat
//
//  Created by Christopher Kobusch on 01.05.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import Foundation
import PeereeCore

/// Informed party for persistance operations.
public protocol PersistedServerChatDataControllerDelegate {
	/// The persisted data has been successfully read from disk.
	func persistedLastReadsLoadedFromDisk(_ lastReads: [PeerID : Date])

	/// Persisting data failed.
	func encodingFailed(with error: Error)

	/// Reading data failed.
	func decodingFailed(with error: Error)
}

/// Controller for disk-operations involving server chat data.
final class PersistedServerChatDataController {
	// MARK: - Public and Internal

	/// Create an instance of `PersistedServerChatDataController`.
	public init(filename: String, targetQueue: DispatchQueue) {
		self.filename = filename
		self.targetQueue = targetQueue
	}

	// MARK: Variables

	/// Informed party.
	public var delegate: PersistedServerChatDataControllerDelegate? = nil

	// MARK: Methods

	/// Removes all associated data of a `PeerID` from disk.
	public func removePeerData(_ peerIDs: Set<PeerID>) {
		targetQueue.async {
			for peerID in peerIDs {
				self.persistedLastReads.removeValue(forKey: peerID)
			}
			self.saveLastReads()
		}
	}

	/// Wipes all data from disk.
	public func clear() {
		targetQueue.async {
			PersistedServerChatDataController.persistenceQueue.async {
				try? FileManager.default.deleteFile(at: self.lastReadsURL)
			}
			self.persistedLastReads = [:]
		}
	}

	/// Read-only access to persisted last read dates.
	public func readLastReads(completion: @escaping ([PeerID : Date]) -> ()) {
		targetQueue.async { completion(self.persistedLastReads) }
	}

	/// Persists persisted last read date of `peerID`.
	public func set(lastRead date: Date, of peerID: PeerID) {
		targetQueue.async {
			self.persistedLastReads[peerID] = date
			self.saveLastReads()
		}
	}

	/// Retrieves all necessary data from disk. You should call this method as soon as possible after creating the `PersistedPeersController`.
	public func loadInitialData() {
		// we need to guarantee that all data is read before it is accessed afterwards,
		// because our targetQueue > persistenceQueue model assumes that the data is succefully read
		targetQueue.async { PersistedServerChatDataController.persistenceQueue.sync {
			self.loadLastReads()
		} }
	}

	// MARK: - Private

	// MARK: Static Constants

	/// File system access queue.
	private static let persistenceQueue = DispatchQueue(label: "de.peeree.PersistedPeersController", qos: .background)

	// MARK: Constants

	/// The queue to access the in-memory data.
	private let targetQueue: DispatchQueue

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
	private func loadLastReads() {
		guard let data = FileManager.default.contents(atPath: self.lastReadsURL.path) else { return }

		let decoder = JSONDecoder()
		do {
			let decodedLastReads = try decoder.decode([PeerID : Date].self, from: data)
			self.targetQueue.async {
				self.persistedLastReads = decodedLastReads
				self.delegate?.persistedLastReadsLoadedFromDisk(decodedLastReads)
			}
		} catch let error {
			self.targetQueue.async { self.delegate?.decodingFailed(with: error) }
		}
	}

	/// Perists all last read dates on disk; must be accessed on targetQueue.
	private func saveLastReads() {
		save(persistedLastReads, at: lastReadsURL)
	}

	/// Persists an `Encodable` `Collection` at `url`.
	private func save<EncodableCollection: Encodable>(_ save: EncodableCollection, at url: URL) where EncodableCollection: Collection {
		PersistedServerChatDataController.persistenceQueue.async {
			do {
				if save.isEmpty {
					try FileManager.default.deleteFile(at: url)
				} else {
					let jsonData = try JSONEncoder().encode(save)
					if !FileManager.default.createFile(atPath: url.path, contents: jsonData, attributes: nil) {
						self.targetQueue.async { self.delegate?.encodingFailed(with: createApplicationError(localizedDescription: "could not create file \(url.path)")) }
					}
				}
			} catch let error {
				self.targetQueue.async { self.delegate?.encodingFailed(with: error) }
			}
		}
	}
}
