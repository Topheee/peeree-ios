//
//  PersistedPeersController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 18.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics
import CryptoKit

import PeereeCore

/// This is basically an actor around a set of PeerInfos. It is simple and stupid, but doesn't need optimization yet.
public actor PersistedPeersController {
	// MARK: - Public and Internal

	public init(filename: String) {
		self.filename = filename
	}

	// MARK: Variables

	/// All saved peer data.
	private(set) var persistedPeers = Set<Peer>()

	// MARK: Methods

	/// Wipes all data from disk.
	public func clear() {
		// Deleting from less to most important files.
		try? fileManager.deleteFile(at: self.thumbnailBaseURL)
		try? fileManager.deleteFile(at: self.biosURL)
		for peer in self.persistedPeers {
			try? fileManager.deleteFile(at: self.pictureURL(of: peer.id.peerID))
		}
		for blob in self.persistedBlobs {
			try? fileManager.deleteFile(at: self.pictureURL(of: blob.key))
		}

		try? fileManager.deleteFile(at: self.peersURL)

		self.persistedPeers = Set<Peer>()
		self.persistedBlobs = [:]
	}

	/// Read-only access to persisted peers.
	public func readPeer(_ peerID: PeerID) -> Peer? {
		self.persistedPeers.first { $0.id.peerID == peerID }
	}

	/// Adds peers to the persisted peers set.
	public func addPeers(_ peers: Set<Peer>) throws {
		self.persistedPeers.formUnion(peers)
		try self.savePeers()
	}

	/// Either edit properties of a peer, delete it from the list (by setting the inout value to nil) or simply find out if it exists in the list.
	public func modify(peerID: PeerID, query: @escaping (inout Peer?) -> ()) throws {
		// find old peer and remove it, if it was present
		var peer = self.persistedPeers.first { $0.id.peerID == peerID }
		_ = peer.map { self.persistedPeers.remove($0) }

		query(&peer)

		// only re-add the peer if it was set
		_ = peer.map { self.persistedPeers.insert($0) }

		// if we run into performance issues, we could check here if really something was modified
		try self.savePeers()
	}

	/// Removes `peers` from the persisted peers set and whipes them and all associated data from disk.
	public func removePeers(_ peers: Set<Peer>) throws {
		self.persistedPeers.subtract(peers)
		for peer in peers {
			self.persistedBlobs.removeValue(forKey: peer.id.peerID)
		}

		for peer in peers {
			try? fileManager.deleteFile(at: self.pictureURL(of: peer.id.peerID))
		}

		try self.savePeers()
		try self.saveBios()
	}

	/// Persists optional peer data.
	public func writeBlob(of peerID: PeerID, query: @escaping (inout PeerBlobData) -> ()) throws {
		let oldBlob = self.persistedBlobs[peerID, default: PeerBlobData()]

		var modifiedBlob = oldBlob
		query(&modifiedBlob)
		self.persistedBlobs[peerID] = modifiedBlob

		if modifiedBlob.biography != oldBlob.biography {
			try self.saveBios()
		}
		if modifiedBlob.portrait != oldBlob.portrait {
			try self.save(portrait: modifiedBlob.portrait, of: peerID)
		}
	}

	/// Retrieves all necessary data from disk. You should call this method as soon as possible after creating the `PersistedPeersController`.
	public func loadInitialData() throws -> [(Peer, PeerBlobData)] {
		// important loads first
		try self.loadPeers()
		try self.loadBios()
		try self.loadThumbnails()

		return self.persistedPeers.map { peer in
			(peer, self.persistedBlobs[peer.id.peerID] ?? PeerBlobData())
		}
	}

	/// Load portrait and hash of `peerID` from disk and informs delegate afterwards.
	public func loadBlob(of peerID: PeerID) -> PeerBlobData? {
		if let blob = self.persistedBlobs[peerID],
		   blob.portrait != nil,
		   blob.portraitHash.count > 0 {
			return blob
		}

		let url = self.pictureURL(of: peerID)
		guard let provider = CGDataProvider(url: url as CFURL) else { return nil }
		guard let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent),
			  let data = provider.data as Data? else {
			elog(Self.LogTag, "getting image or data from CGDataProvider failed.")
			return nil
		}

		let hash = Data(SHA256.hash(data: data))

		let result: PeerBlobData

		if let blob = self.persistedBlobs[peerID] {
			result = PeerBlobData(
				biography: blob.biography, portraitHash: hash,
				portrait: image, thumbnail: blob.thumbnail)
		} else {
			result = PeerBlobData(
				portraitHash: hash, portrait: image, thumbnail: nil)
		}

		self.persistedBlobs[peerID] = result

		return result
	}

	// MARK: - Private

	// MARK: Static Constants

	// Log tag.
	private static let LogTag = "PersistedPeersController"

	// MARK: Constants

	private let fileManager = FileManager()

	/// Base file name for all files created by an instance of this class.
	private let filename: String

	// MARK: Variables

	/// Locator of file containing all peer data; thread-safe.
	private var peersURL: URL {
		// Create a file path to our documents directory
		let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
		return URL(fileURLWithPath: paths[0]).appendingPathComponent(filename, isDirectory: false)
	}

	/// Locator of file containing all biographies; thread-safe.
	private var biosURL: URL {
		// Create a file path to our documents directory
		let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
		return URL(fileURLWithPath: paths[0]).appendingPathComponent("\(filename).bios.txt", isDirectory: false)
	}

	/// Locator of folder containing all thumbnails; thread-safe.
	private var thumbnailBaseURL: URL {
		let paths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
		return URL(fileURLWithPath: paths[0]).appendingPathComponent("\(filename).thumbnails", isDirectory: true)
	}

	/// Locator of file containing the portrait of `peerID` (if available); thread-safe.
	private func pictureURL(of peerID: PeerID) -> URL {
		// Create a file path to our documents directory
		let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
		return URL(fileURLWithPath: paths[0]).appendingPathComponent("\(filename).\(peerID.uuidString).jpeg", isDirectory: false)
	}

	/// Locator of file containing the portrait of `peerID` (if available); thread-safe.
	private func thumbnailURL(of peerID: PeerID, base: URL) -> URL {
		return base.appendingPathComponent("\(peerID.uuidString).jpeg", isDirectory: false)
	}

	/// All peristed optional peer data; must be accessed on targetQueue.
	private var persistedBlobs = [PeerID : PeerBlobData]()

	// MARK: Methods

	/// Retrieves all saved peers from disk; call from `persistenceQueue` only.
	private func loadPeers() throws {
		guard let data = fileManager.contents(atPath: self.peersURL.path) else { return }

		let decoder = JSONDecoder()

		do {
			let decodedPeers = try decoder.decode(Set<Peer>.self, from: data)
			self.persistedPeers = decodedPeers
		} catch {
			wlog(
				Self.LogTag, "Decoding persisted peers failed: \(error). " +
				"Attempting migration from version 1.6.4")

			let decodedPeers = try decoder.decode([Peer1_6_4].self, from: data)

			// sanity check
			try decodedPeers.forEach {
				let m = $0.modernized()
				_ = try m.id.publicKey()
			}

			self.persistedPeers = Set(decodedPeers.map { $0.modernized() })
		}
	}

	/**
	 Retrieves all saved biographies from disk; call from `persistenceQueue` only.
	 - Warning: This will overwrite possibly loaded portraits! You should always call it as soon as possible after creating the `PersistedPeersController`.
	 */
	private func loadBios() throws {
		guard let data = fileManager.contents(atPath: self.biosURL.path) else { return }

		let decoder = JSONDecoder()
		let decodedBios = try decoder.decode([PeerID : String].self, from: data)
		self.persistedBlobs = decodedBios.mapValues { bio in
			PeerBlobData(biography: bio, portrait: nil)
		}
	}

	/**
	 Retrieves all already calculated portrait thumbnails from disk; call from `persistenceQueue` only.
	 */
	private func loadThumbnails() throws {
		guard let enumerator = fileManager.enumerator(atPath: self.thumbnailBaseURL.path) else { return }

		var thumbnails = [PeerID : CGImage]()

		enumerator.skipDescendants()
		while let path = enumerator.nextObject() as? String {
			let url = URL(fileURLWithPath: path, isDirectory: false)
			let uuidString = url.deletingPathExtension().lastPathComponent

			guard let peerID = PeerID(uuidString: uuidString),
				  let provider = CGDataProvider(url: url as CFURL) else { continue }

			guard let image = CGImage(jpegDataProviderSource: provider,
									  decode: nil, shouldInterpolate: true,
									  intent: CGColorRenderingIntent.defaultIntent) else {
				elog(Self.LogTag, "getting image or data from CGDataProvider failed.")

				try? fileManager.deleteFile(at: url)
				continue
			}

			thumbnails[peerID] = image
		}

		for entry in thumbnails {
			if let blob = self.persistedBlobs[entry.key] {
				self.persistedBlobs[entry.key] = PeerBlobData(biography: blob.biography, portraitHash: blob.portraitHash, portrait: blob.portrait, thumbnail: entry.value)
			} else {
				self.persistedBlobs[entry.key] = PeerBlobData(thumbnail: entry.value)
			}
		}
	}

	/// Persists an `Encodable` `Collection` at `url`.
	private func save<EncodableCollection: Encodable>(_ save: EncodableCollection, at url: URL) throws where EncodableCollection: Collection {
		if save.isEmpty {
			try fileManager.deleteFile(at: url)
		} else {
			let jsonData = try JSONEncoder().encode(save)
			guard fileManager.createFile(atPath: url.path, contents: jsonData, attributes: nil) else {
				throw createApplicationError(localizedDescription: "could not create file \(url.path)")
			}
		}
	}

	/// Persists all peer data; must be accessed on targetQueue.
	private func savePeers() throws {
		// create a copy of the value we want to save, still faster than the encoding
		try save(persistedPeers, at: peersURL)
	}

	/// Perists all bios on disk; must be accessed on targetQueue.
	private func saveBios() throws {
		// create a copy of the value we want to save, still faster than the encoding
		// note: this won't remove the entries for deleted peers, since the empty string is still persisted
		try save(persistedBlobs.mapValues { value in value.biography }, at: biosURL)
	}

	/// Persists `portrait` on disk; call only from targetQueue.
	private func save(portrait: CGImage?, of peerID: PeerID) throws {
		let url = self.pictureURL(of: peerID)
		if let pic = portrait {
			try pic.save(to: url, compressionQuality: StandardPortraitCompressionQuality)
		} else {
			try fileManager.deleteFile(at: url)
		}
	}
}

/// All optional, large info a user configures, which is loaded in the background while the peer is already being presented.
public struct PeerBlobData: Sendable {
	public var biography = ""
	public var portraitHash = Data()
	public var portrait: CGImage?
	public var thumbnail: CGImage?
}

extension PeerBlobData {
	/// Binary representation of `biography`.
	public var biographyData: Data {
		get { return biography.data(prefixedEncoding: biography.smallestEncoding)! }
		set { biography = String(dataPrefixedEncoding: newValue) ?? "😬" }
	}
}

