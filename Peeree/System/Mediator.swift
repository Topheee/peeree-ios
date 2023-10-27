//
//  Mediator.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.04.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import UIKit
import PeereeCore
import PeereeServerChat
import PeereeDiscovery
import KeychainWrapper
import PeereeServer

extension PeerViewModel {
	/// Objectionable content classification required by the App Store.
	public var pictureClassification: ContentClassification {
		return pictureHash.map { PeereeIdentityViewModelController.classify(imageHash: $0) } ?? .none
	}
}

/// This singleton ties all Peeree modules together.
final class Mediator {

	// Log tag.
	private static let LogTag = "Mediator"

	/// Singleton instance.
	public static let shared = Mediator()

	/// Observes relevant notifications in `NotificationCenter`.
	private func observeNotifications() {
		let pinStateChangeHandler: (PeerID, Notification) -> Void = { peerID, _ in
			ServerChatFactory.chat { sc in
				sc?.leaveChat(with: peerID)
			}
		}

		notificationObservers.append(AccountControllerFactory.NotificationName.accountCreated.addObserver { _ in
			// hack: this will sync the UserPeer to the ViewModel
			UserPeer.instance.modifyInfo { _ in }

			PeeringController.shared.checkPeering { peering in
				guard peering else { return }

				PeeringController.shared.startAdvertising(restartOnly: false)
			}
		})

		notificationObservers.append(AccountControllerFactory.NotificationName.accountDeleted.addObserver { _ in
			PeeringController.shared.teardown()
		})

		notificationObservers.append(AccountController.NotificationName.unpinned.addAnyPeerObserver(pinStateChangeHandler))
		notificationObservers.append(AccountController.NotificationName.unmatch.addAnyPeerObserver(pinStateChangeHandler))

		notificationObservers.append(AccountController.NotificationName.pinMatch.addAnyPeerObserver { peerID, _ in
			ServerChatFactory.chat { sc in
				sc?.initiateChat(with: peerID)
			}
		})
	}

	/// Observes notifications.
	private init() {
		observeNotifications()
	}

	/// All references to NotificationCenter observers by this object.
	private var notificationObservers: [Any] = []
}


// MARK: - Server Chat

// MARK: ServerChatDelegate

extension Mediator: ServerChatDelegate {
	func decodingPersistedChatDataFailed(with error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: "Error")
	}

	func encodingPersistedChatDataFailed(with error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: "Error")
	}

	func configurePusherFailed(_ error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Push Notifications Unavailable", comment: "Title of alert."))
	}

	func cannotJoinRoom(_ error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Cannot Join Room", comment: "Title of alert."))
	}

	func decryptionError(_ error: Error, peerID: PeerID, recreateRoom: @escaping @Sendable () -> Void) {
		DispatchQueue.main.async {
			let name = PeerViewModelController.shared.viewModels[peerID]?.info.nickname ?? peerID.uuidString

			let alertTitle = NSLocalizedString("Broken Chatroom", comment: "Title of broken room alert")
			let alertBody = String(format: NSLocalizedString("broken_chatroom_content", comment: "Content of broken room alert."), name, error.localizedDescription)
			let recreateRoomButtonTitle = NSLocalizedString("Re-create room", comment: "Caption of button.")

			let alertController = UIAlertController(title: alertTitle, message: alertBody, preferredStyle: UIDevice.current.iPadOrMac ? .alert : .actionSheet)
			let createAction = UIAlertAction(title: recreateRoomButtonTitle, style: .`default`) { (_) in
				recreateRoom()
			}
			alertController.addAction(createAction)
			alertController.addCancelAction()
			alertController.preferredAction = createAction
			alertController.present()
		}
	}

	func serverChatCertificateIsInvalid() {
		DispatchQueue.main.async {
			let error = createApplicationError(localizedDescription: NSLocalizedString("chat_server_cert_invalid", comment: "User-facing security error."))
			InAppNotificationController.display(serverChatError: .fatal(error), localizedTitle: NSLocalizedString("Connection to Chat Server Failed", comment: "Error message title"))
		}
	}

	func serverChatClosed(error: Error?) {
		ServerChatViewModelController.shared.clearTranscripts()

		error.map {
			InAppNotificationController.display(error: $0, localizedTitle: NSLocalizedString("Connection to Chat Server Lost", comment: "Error message title"))
		}
	}

	func serverChatInternalErrorOccured(_ error: Error) {
		elog(Self.LogTag, "internal server chat error \(error)")
	}
}

// MARK: ServerChatDataSource
extension Mediator: ServerChatDataSource {
	public func hasPinMatch(with peerIDs: [PeerID], forceCheck: Bool, _ result: @escaping (PeerID, Bool) -> ()) {
		AccountControllerFactory.shared.use { ac in
			peerIDs.forEach { peerID in
				ac.updatePinStatus(of: peerID, force: forceCheck) { state in
					result(peerID, state == PinState.pinMatch)
				}
			}
		}
	}
}


// MARK: - Discovery


// MARK: PeeringControllerDataSource
extension Mediator: PeeringControllerDataSource {
	func cleanup(allPeers: [PeereeIdentity], _ result: @escaping ([PeerID]) -> ()) {
		AccountControllerFactory.shared.use({ ac in
			// never remove our own view model or the view model of pinned peers
			result(allPeers.filter { $0.peerID != ac.peerID && !ac.isPinned($0) }.map { $0.peerID })
		}, { error in
			error.map { flog(Self.LogTag, $0.localizedDescription) }
			result([])
		})
	}

	func getIdentity(_ result: @escaping (PeereeIdentity, KeyPair) -> ()) {
		AccountControllerFactory.shared.use { ac in
			result(ac.identity, ac.keyPair)
		}
	}

	func verify(_ peerID: PeerID, nonce: Data, signature: Data, _ result: @escaping (Bool) -> ()) {
		AccountControllerFactory.shared.use { ac in
			// we need to compute the verification in all cases, because if we would only do it if we have a public key available, it takes less time to fail if we did not pin the attacker -> timing attack: the attacker can deduce whether we pinned him, because he sees how much time it takes to fulfill their request
			do {
				let id = try ac.id(of: peerID)
				try id.publicKey.verify(message: nonce, signature: signature)

				// we need to check if we pin MATCHED the peer, because if we would sent him a successful authentication return code while he did not already pin us, it means he can see that we pinned him
				result(ac.hasPinMatch(peerID))
			} catch let exc {
				elog(Self.LogTag, "A peer tried to authenticate to us as \(peerID). Message: \(exc.localizedDescription)")
				result(false)
			}
		}
	}
}

// MARK: PeeringControllerDelegate
extension Mediator: PeeringControllerDelegate {
	func advertisingStopped(with error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Bluetooth Publish Failed", comment: "Error title"))
	}

	func bluetoothNetwork(isAvailable: Bool) {
		PeeringController.shared.change(peering: isAvailable)
	}

	func encodingPeersFailed(with error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Encoding Recent Peers Failed", comment: "Low-level error"))
	}

	func decodingPeersFailed(with error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Decoding Recent Peers Failed", comment: "Low-level error"))
	}
}

// MARK: UserPeerDelegate
extension Mediator: UserPeerDelegate {
	func syncToViewModel(info: PeerInfo, bio: String, pic: CGImage?) {
		AccountControllerFactory.shared.use { ac in
			// we must access AccountController properties on its `dQueue`
			let peerID = ac.peerID

			let publicKeyData: Data
			do {
				publicKeyData = try ac.keyPair.publicKey.externalRepresentation()
			} catch {
				assertionFailure(error.localizedDescription)
				return
			}

			DispatchQueue.main.async {
				let id: PeereeIdentity
				do {
					id = try PeereeIdentity(peerID: peerID, publicKeyData: publicKeyData)
				} catch {
					assertionFailure(error.localizedDescription)
					return
				}

				PeereeIdentityViewModelController.insert(model: PeereeIdentityViewModel(id: id))
				PeerViewModelController.shared.update(peerID, info: info, lastSeen: Date())
				PeerViewModelController.shared.modify(peerID: peerID) { model in
					model.isAvailable = true
					model.biography = bio
					if let portrait = pic {
						model.loaded(portrait: portrait, hash: Data())
					} else {
						model.deletePortrait()
					}
				}
			}
		}
	}
}


// MARK: - Social Graph

// MARK: AccountControllerDelegate
extension Mediator: AccountControllerDelegate {
	func pin(of peerID: PeerID, failedWith error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Pin Failed", comment: "Title of in-app error notification"))
	}

	func publicKeyMismatch(of peerID: PeerID) {
		DispatchQueue.main.async {
			let name = PeerViewModelController.shared.viewModel(of: peerID).info.nickname
			let message = String(format: NSLocalizedString("The identity of %@ is invalid.", comment: "Message of Possible Malicious Peer alert"), name)
			let error = createApplicationError(localizedDescription: message)
			InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Possible Malicious Peer", comment: "Title of public key mismatch in-app notification"))
		}
	}

	func sequenceNumberResetFailed(error: Error) {
		DispatchQueue.main.async {
			InAppNotificationController.display(openapiError: error,
												localizedTitle: NSLocalizedString("Resetting Server Nonce Failed",
																				  comment: "Title of sequence number reset failure alert"),
												furtherDescription: NSLocalizedString("The server nonce is used to secure your connection.",
																					  comment: "Further description of Resetting Server Nonce Failed alert"))
		}
	}

	func sequenceNumberReset() {
		InAppNotificationController.display(title: NSLocalizedString("Request Failed", comment: "Error title"), message: NSLocalizedString("A request has failed, please try again.", comment: "Error body"))
	}
}
