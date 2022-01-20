//
//  PinMatchesController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 24.05.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import Foundation

final class PinMatchesController: PersistedPeersControllerDelegate {
	public enum Notifications: String {
		case pinMatchedPeersUpdated
	}

	static let shared = PinMatchesController()

	let persistence = PersistedPeersController(filename: "pin-matched-peers.json")

	private var notificationObservers: [NSObjectProtocol] = []

	private init() {
		notificationObservers.append(PeeringController.Notifications.peerAppeared.addPeerObserver { (peerID, notification) in
			let again = notification.userInfo?[PeeringController.NotificationInfoKey.again.rawValue] as? Bool ?? false
			if !again { self.refresh(peerID: peerID) }
		})
		notificationObservers.append(AccountController.Notifications.pinMatch.addPeerObserver { peerID, _ in
			guard let peer = PeeringController.shared.manager(for: peerID).peerInfo else { return }
			self.persistence.write { peers in
				peers.insert(peer)
			}
		})
		notificationObservers.append(AccountController.Notifications.accountDeleted.addObserver { _ in
			// delete all cached pictures and finally the persisted PeerInfo records themselves
			self.persistence.write { peers in
				PeeringController.shared.managers(for: peers.map { $0.peerID }) { peerManagers in
					peerManagers.forEach { $0.deletePicture() }
				}
				peers = []
			}
		})
		notificationObservers.append(AccountController.Notifications.unpinned.addPeerObserver { peerID, _ in
			if let peer = PeeringController.shared.manager(for: peerID).peerInfo {
				self.persistence.write { peers in
					peers.remove(peer)
				}
			} else {
				self.persistence.write { peers in
					guard let index = (peers.firstIndex { peer in
						return peer.peerID == peerID
					}) else { return }
					peers.remove(at: index)
				}
			}

		})
	}

	deinit {
		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	// MARK: - PersistedPeersControllerDelegate

	func persistedPeersUpdated() {
		persistence.read { peers in
			// load PeerInfos into PeerManagers
			PeeringController.shared.managers(for: peers.map { $0.peerID }) { managers in
				for manager in managers {
					// this will trigger the load
					_ = manager.peerInfo
				}
			}
			Notifications.pinMatchedPeersUpdated.postAsNotification(object: self, userInfo: nil)
		}
	}

	func encodingFailed(with error: Error) {
		AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Encoding Pin Match Peers Failed", comment: "Low-level error"), furtherDescription: nil)
	}

	func decodingFailed(with error: Error) {
		AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Decoding Pin Match Peers Failed", comment: "Low-level error"), furtherDescription: nil)
	}

	// MARK: Private Methods

	private func refresh(peerID: PeerID) {
		guard let peer = PeeringController.shared.manager(for: peerID).peerInfo else { return }

		self.persistence.write { peers in
			peers.remove(peer)
			if peer.pinMatched { peers.insert(peer) }
		}
	}
}
