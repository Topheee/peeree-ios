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
		case pinMatchedPeersUpdated
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
					Notifications.pinMatchedPeersUpdated.postAsNotification(object: self)
				}
			} catch let error {
				NSLog("ERROR: Couldn't decode pinMatchedPeers: \(error.localizedDescription)")
			}
		}

		notificationObservers.append(PeeringController.Notifications.peerAppeared.addPeerObserver { (peerID, notification) in
			let again = notification.userInfo?[PeeringController.NotificationInfoKey.again.rawValue] as? Bool ?? false
			if !again { self.reload(peerID: peerID) }
		})
		notificationObservers.append(AccountController.Notifications.pinMatch.addPeerObserver { peerID, _ in
			guard let peer = PeeringController.shared.manager(for: peerID).peerInfo else { return }
			DispatchQueue.main.async {
				self.pinMatchedPeers.insert(peer)
				self.savePinMatchedPeers()
			}
		})
		notificationObservers.append(AccountController.Notifications.accountDeleted.addObserver { _ in
			DispatchQueue.main.async {
				PeeringController.shared.managers(for: self.pinMatchedPeers.map { $0.peerID }) { peerManagers in
					peerManagers.forEach { $0.deletePicture() }
				}
				self.pinMatchedPeers = []
				self.savePinMatchedPeers()
			}
		})
		notificationObservers.append(AccountController.Notifications.unpinned.addPeerObserver { peerID, _ in
			if let peer = PeeringController.shared.manager(for: peerID).peerInfo {
				DispatchQueue.main.async {
					if self.pinMatchedPeers.remove(peer) != nil {
						self.savePinMatchedPeers()
					}
				}
			} else {
				DispatchQueue.main.async {
					guard let index = (self.pinMatchedPeers.firstIndex { peer in
						return peer.peerID == peerID
					}) else { return }
					self.pinMatchedPeers.remove(at: index)
					self.savePinMatchedPeers()
				}
			}

		})
	}

	deinit {
		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	/// thread-safety: call only from main thread!
	func peerInfo(for peerID: PeerID) -> PeerInfo? {
		return pinMatchedPeers.first { $0.peerID == peerID }
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
		// TODO PERFORMANCE: only inform about the changed peer(s)
		Notifications.pinMatchedPeersUpdated.postAsNotification(object: self)
	}

	private func reload(peerID: PeerID) {
		guard let peer = PeeringController.shared.manager(for: peerID).peerInfo else { return }

		DispatchQueue.main.async {
			// TODO PERFORMANCE: only replace and save if really something changed
			self.pinMatchedPeers.remove(peer)
			if peer.pinMatched { self.pinMatchedPeers.insert(peer) }
			self.savePinMatchedPeers()
		}
	}
}
