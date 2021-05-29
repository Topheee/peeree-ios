//
//  PinMatchesController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 24.05.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import Foundation

final class PinMatchesController {
	private static var resourceURL: URL {
		// Create a file path to our documents directory
		let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
		return URL(fileURLWithPath: paths[0]).appendingPathComponent("pin-matched-peers.json", isDirectory: false)
	}

	public enum Notifications: String {
		case pinMatchedPeersLoaded
	}

	static let shared = PinMatchesController()

	/// thread-safety: only access from main queue!
	private(set) var pinMatchedPeers = Set<PeerInfo>()

	private var notificationObservers: [NSObjectProtocol] = []

	private init() {
		DispatchQueue.global(qos: .background).async {
			guard let data = FileManager.default.contents(atPath: PinMatchesController.resourceURL.path) else { return }

			let decoder = JSONDecoder()
			do {
				let decodedPeers = try decoder.decode(Set<PeerInfo>.self, from: data)
				DispatchQueue.main.async {
					self.pinMatchedPeers = decodedPeers
					Notifications.pinMatchedPeersLoaded.postAsNotification(object: self)
				}
			} catch let error {
				NSLog("ERROR: Couldn't decode pinMatchedPeers: \(error.localizedDescription)")
			}
		}

		notificationObservers.append(PeeringController.Notifications.peerAppeared.addPeerObserver { [weak self] (peerID, notification) in
			let again = notification.userInfo?[PeeringController.NotificationInfoKey.again.rawValue] as? Bool ?? false
			if !again { self?.reload(peerID: peerID) }
		})
		notificationObservers.append(AccountController.Notifications.pinMatch.addPeerObserver { [weak self] peerID, _ in
			guard let strongSelf = self,
				  let peer = PeeringController.shared.manager(for: peerID).peerInfo else { return }
			strongSelf.pinMatchedPeers.insert(peer)
			strongSelf.savePinMatchedPeers()
		})
		notificationObservers.append(AccountController.Notifications.unpinned.addPeerObserver { [weak self] peerID, _ in
			guard let strongSelf = self else { return }
			if let peer = PeeringController.shared.manager(for: peerID).peerInfo {
				DispatchQueue.main.async {
					if strongSelf.pinMatchedPeers.remove(peer) != nil {
						strongSelf.savePinMatchedPeers()
					}
				}
			} else {
				DispatchQueue.main.async {
					guard let index = (strongSelf.pinMatchedPeers.firstIndex { peer in
						return peer.peerID == peerID
					}) else { return }
					strongSelf.pinMatchedPeers.remove(at: index)
					strongSelf.savePinMatchedPeers()
				}
			}

		})
	}

	deinit {
		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	func clear() {
		DispatchQueue.main.async {
			self.pinMatchedPeers.removeAll()
		}
	}

	// MARK: Private Methods

	/// thread-safety: call from main thread only!
	private func savePinMatchedPeers() {
		// create a copy of the value we want to save, still faster than the encoding
		let save = pinMatchedPeers
		DispatchQueue.global(qos: .background).async {
			do {
				let jsonData = try JSONEncoder().encode(save)
				try? FileManager.default.removeItem(at: PinMatchesController.resourceURL)
				if !FileManager.default.createFile(atPath: PinMatchesController.resourceURL.path, contents: jsonData, attributes: nil) {
					NSLog("ERROR: Couldn't persist pin matched peers file.")
				}
			} catch let error {
				NSLog("ERROR: Couldn't encode JSON: \(error.localizedDescription)")
			}
		}
	}

	private func reload(peerID: PeerID) {
		guard let peer = PeeringController.shared.manager(for: peerID).peerInfo else { return }

		DispatchQueue.main.async {
			// TODO PERFORMANCE: only replace and save if really something changed
			self.pinMatchedPeers.remove(peer)
			self.pinMatchedPeers.insert(peer)
			self.savePinMatchedPeers()
		}
	}
}
