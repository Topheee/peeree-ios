//
//  PersistedPeersController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 18.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics

public protocol PersistedPeersControllerDelegate {
	func persistedPeersLoadedFromDisk(_ peers: Set<Peer>)
	func persistedBiosLoadedFromDisk(_ bios: [PeerID : String])
	func portraitLoadedFromDisk(_ portrait: CGImage, of peerID: PeerID, hash: Data)
	func encodingFailed(with error: Error)
	func decodingFailed(with error: Error)
}

/// This is basically an actor around a set of PeerInfos. It is simple and stupid, but doesn't need optimization yet.
public final class PersistedPeersController {
	// MARK: - Public and Internal

	public init(filename: String, targetQueue: DispatchQueue) {
		self.filename = filename
		self.targetQueue = targetQueue
	}

	// MARK: Static Constants

	/// The JPEG compression quality when saving peers to disk.
	public static let StandardPortraitCompressionQuality: CGFloat = 0.0

	// MARK: Variables

	public var delegate: PersistedPeersControllerDelegate? = nil

	// MARK: Methods

	/// Wipes all data from disk.
	public func clear() {
		targetQueue.async {
			let peers = self.persistedPeers
			let blobs = self.persistedBlobs
			PersistedPeersController.persistenceQueue.async {
				try? self.deleteFile(at: self.biosURL)
				try? self.deleteFile(at: self.peersURL)
				for peer in peers {
					try? self.deleteFile(at: self.pictureURL(of: peer.id.peerID))
				}
				for blob in blobs {
					try? self.deleteFile(at: self.pictureURL(of: blob.key))
				}
			}
			self.persistedPeers = Set<Peer>()
			self.persistedBlobs = [:]
		}
	}

	/// Read-only access to persisted peers.
	public func readPeers(completion: @escaping (Set<Peer>) -> ()) {
		targetQueue.async { completion(self.persistedPeers) }
	}

	/// Adds peers to the persisted peers set.
	public func addPeers(query: @escaping () -> (Set<Peer>)) {
		targetQueue.async {
			self.persistedPeers.formUnion(query())
			self.savePeers()
		}
	}

	/// Either edit properties of a peer, delete it from the list (by setting the inout value to nil) or simply find out if it exists in the list.
	public func modify(peerID: PeerID, query: @escaping (inout Peer?) -> ()) {
		targetQueue.async {
			// find old peer and remove it, if it was present
			var peer = self.persistedPeers.first { $0.id.peerID == peerID }
			_ = peer.map { self.persistedPeers.remove($0) }

			query(&peer)

			// only re-add the peer if it was set
			_ = peer.map { self.persistedPeers.insert($0) }

			// if we run into performance issues, we could check here if really something was modified
			self.savePeers()
		}
	}

	/// Removes the returned `Peer` instances of `query` from the persisted peers set.
	public func filterPeers(query: @escaping (Set<Peer>) -> (Set<Peer>)) {
		targetQueue.async {
			let removedPeers = query(self.persistedPeers)
			self.persistedPeers.subtract(removedPeers)
			for peer in removedPeers {
				self.persistedBlobs.removeValue(forKey: peer.id.peerID)
			}
			PersistedPeersController.persistenceQueue.async {
				for peer in removedPeers {
					try? self.deleteFile(at: self.pictureURL(of: peer.id.peerID))
				}
			}
			self.savePeers()
			self.saveBios()
		}
	}

	/// Reads optional peer data.
	public func readBlob(of peerID: PeerID, completion: @escaping (PeerBlobData) -> ()) {
		targetQueue.async { completion(self.persistedBlobs[peerID] ?? PeerBlobData()) }
	}

	/// Persists optional peer data.
	public func writeBlob(of peerID: PeerID, completion: @escaping (inout PeerBlobData) -> ()) {
		targetQueue.async {
			let oldBlob = self.persistedBlobs[peerID, default: PeerBlobData()]
			var modifiedBlob = oldBlob
			completion(&modifiedBlob)
			self.persistedBlobs[peerID] = modifiedBlob
			if modifiedBlob.biography != oldBlob.biography {
				self.saveBios()
			}
			if modifiedBlob.portrait != oldBlob.portrait {
				self.save(portrait: modifiedBlob.portrait, of: peerID)
			}
		}
	}

	/// Retrieves all saved peers from disk. You should call this method as soon as possible after creating the `PersistedPeersController`.
	func loadPeers() {
		PersistedPeersController.persistenceQueue.async {
			guard let data = FileManager.default.contents(atPath: self.peersURL.path) else { return }

			let decoder = JSONDecoder()
			do {
				let decodedPeers = try decoder.decode(Set<Peer>.self, from: data)
				self.targetQueue.async {
					self.persistedPeers = decodedPeers
					self.delegate?.persistedPeersLoadedFromDisk(decodedPeers)
				}
			} catch let error {
				self.targetQueue.async { self.delegate?.decodingFailed(with: error) }
			}
		}
	}

	/**
	 Retrieves all saved biographies from disk.
	 - Warning: This will overwrite possibly loaded portraits! You should always call it as soon as possible after creating the `PersistedPeersController`.
	 */
	func loadBios() {
		PersistedPeersController.persistenceQueue.async {
			guard let data = FileManager.default.contents(atPath: self.biosURL.path) else { return }

			let decoder = JSONDecoder()
			do {
				let decodedBios = try decoder.decode([PeerID : String].self, from: data)
				self.targetQueue.async {
					self.persistedBlobs = decodedBios.mapValues { bio in
						PeerBlobData(biography: bio, portrait: nil)
					}
					self.delegate?.persistedBiosLoadedFromDisk(decodedBios)
				}
			} catch let error {
				self.targetQueue.async { self.delegate?.decodingFailed(with: error) }
			}
		}
	}

	/// Load portrait of `peerID` from disk and informs delegate afterwards.
	public func loadPortrait(of peerID: PeerID) {
		// TODO: prevent double work
		// currently, we may load the same portrait over and over, either while it is still being load or even if it was already loaded succesfully once
		// we would need to introduce a variable isLoadingPortrait per PeerID, which we would check and set on targetQueue before and after loading bzw. ne, sogar loading state: not loaded, loading, loaded
		PersistedPeersController.persistenceQueue.async {
			let url = self.pictureURL(of: peerID)
			guard let provider = CGDataProvider(url: url as CFURL) else {
				NSLog("ERROR: could not initialize CGDataProvider.")
				return
			}
			guard let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent),
				  let data = provider.data as Data? else {
				NSLog("ERROR: getting image or data from CGDataProvider failed.")
				return
			}

			self.targetQueue.async {
				self.persistedBlobs[peerID]?.portrait = image
				self.delegate?.portraitLoadedFromDisk(image, of: peerID, hash: data.sha256())
			}
		}
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

	/// Locator of file containing the portrait of `peerID` (if available); thread-safe.
	private func pictureURL(of peerID: PeerID) -> URL {
		// Create a file path to our documents directory
		let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
		return URL(fileURLWithPath: paths[0]).appendingPathComponent("\(filename).\(peerID.uuidString).jpeg", isDirectory: false)
	}

	/// All saved peer data; must be accessed on targetQueue.
	private var persistedPeers = Set<Peer>()
	/// All peristed optional peer data; must be accessed on targetQueue.
	private var persistedBlobs = [PeerID : PeerBlobData]()

	// MARK: Methods

	/// Persists all peer data; must be accessed on targetQueue.
	private func savePeers() {
		// create a copy of the value we want to save, still faster than the encoding
		let save = self.persistedPeers
		PersistedPeersController.persistenceQueue.async {
			let url = self.peersURL
			do {
				if save.isEmpty {
					try self.deleteFile(at: url)
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

	/// Perists all bios on disk; must be accessed on targetQueue.
	private func saveBios() {
		// create a copy of the value we want to save, still faster than the encoding
		// note: this won't remove the entries for deleted peers, since the empty string is still persisted
		let save = self.persistedBlobs.mapValues { value in value.biography }
		PersistedPeersController.persistenceQueue.async {
			let url = self.biosURL
			do {
				if save.isEmpty {
					try self.deleteFile(at: url)
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

	/// Persists `portrait` on disk; call only from targetQueue.
	private func save(portrait: CGImage?, of peerID: PeerID) {
		// create a copy of the value we want to save, still faster than the encoding
		PersistedPeersController.persistenceQueue.async {
			do {
				let url = self.pictureURL(of: peerID)
				if let pic = portrait {
					try pic.save(to: url, compressionQuality: PersistedPeersController.StandardPortraitCompressionQuality)
				} else {
					try self.deleteFile(at: url)
				}
			} catch let error {
				self.targetQueue.async { self.delegate?.encodingFailed(with: error) }
			}
		}
	}

	/// Purges a file from disk if it exists; call only from persistenceQueue.
	private func deleteFile(at url: URL) throws {
		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: url.path) {
			try fileManager.removeItem(at: url)
		}
	}
}

/// All optional, large info a user configures, which is loaded in the background while the peer is already being presented.
public struct PeerBlobData {
	public var biography = ""
	public var portrait: CGImage?
}

extension PeerBlobData {
	/// Binary representation of `biography`.
	public var biographyData: Data {
		get { return biography.data(prefixedEncoding: biography.smallestEncoding)! }
		set { biography = String(dataPrefixedEncoding: newValue) ?? "😬" }
	}
}

