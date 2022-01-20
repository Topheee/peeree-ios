//
//  PersistedPeersController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 18.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation

protocol PersistedPeersControllerDelegate {
	func persistedPeersUpdated()
	func encodingFailed(with error: Error)
	func decodingFailed(with error: Error)
}

/// This is basically an actor around a set of PeerInfos. It is simple and stupid, but doesn't need optimization yet.
final class PersistedPeersController {
	private static let queue = DispatchQueue(label: "de.peeree.PersistedPeersController", qos: .background)
	private let targetQueue: DispatchQueue
	private let filename: String

	private var resourceURL: URL {
		// Create a file path to our documents directory
		let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
		return URL(fileURLWithPath: paths[0]).appendingPathComponent(filename, isDirectory: false)
	}

	// must be accessed on targetQueue
	private var persistedPeers = Set<PeerInfo>()

	var delegate: PersistedPeersControllerDelegate? = nil

	init(filename: String, targetQueue: DispatchQueue = DispatchQueue.main) {
		self.filename = filename
		self.targetQueue = targetQueue

		loadPeers()
	}

	func read(completion: @escaping (Set<PeerInfo>) -> ()) {
		targetQueue.async { completion(self.persistedPeers) }
	}

	func write(completion: @escaping (inout Set<PeerInfo>) -> ()) {
		targetQueue.async {
			completion(&self.persistedPeers)
			self.savePeers()
		}
	}

	// MARK: Private Methods

	// must be accessed on targetQueue
	private func savePeers() {
		// create a copy of the value we want to save, still faster than the encoding
		let save = self.persistedPeers
		PersistedPeersController.queue.async {
			do {
				if save.isEmpty {
					try FileManager.default.removeItem(at: self.resourceURL)
				} else {
					let jsonData = try JSONEncoder().encode(save)
					if !FileManager.default.createFile(atPath: self.resourceURL.path, contents: jsonData, attributes: nil) {
						self.targetQueue.async { self.delegate?.encodingFailed(with: createApplicationError(localizedDescription: "could not create file \(self.resourceURL.path)")) }
					}
				}
			} catch let error {
				self.targetQueue.async { self.delegate?.encodingFailed(with: error) }
			}
			self.targetQueue.async { self.delegate?.persistedPeersUpdated() }
		}
	}

	private func loadPeers() {
		PersistedPeersController.queue.async {
			guard let data = FileManager.default.contents(atPath: self.resourceURL.path) else { return }

			let decoder = JSONDecoder()
			do {
				let decodedPeers = try decoder.decode(Set<PeerInfo>.self, from: data)
				self.targetQueue.async {
					self.persistedPeers = decodedPeers
					self.delegate?.persistedPeersUpdated()
				}
			} catch let error {
				self.targetQueue.async { self.delegate?.decodingFailed(with: error) }
			}
		}
	}
}

