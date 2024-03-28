//
//  Mediator.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.04.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import CoreGraphics
import UIKit
import Combine

import PeereeCore
import PeereeServerChat
import PeereeDiscovery
import KeychainWrapper
import PeereeServer

extension DiscoveryPerson {
	/// Objectionable content classification required by the App Store.
	@MainActor
	public var pictureClassification: ContentClassification {
		return SocialViewState.shared.classify(imageHash: pictureHash)
	}
}

/// This singleton ties all Peeree modules together.
final class Mediator {

	// Log tag.
	private static let LogTag = "Mediator"

	/// Singleton instance.
	public static let shared = Mediator()

	let notificationManager = NotificationManager()

	private var peeringController: PeeringController?

	/// Observes relevant notifications in `NotificationCenter`.
	private func observeNotifications() {
		let pinStateChangeHandler: (PeerID, Notification) -> Void = { peerID, _ in
			ServerChatFactory.chat { sc in
				sc?.leaveChat(with: peerID)
			}
		}

		notificationObservers.append(UserPeer.NotificationName.changed.addObserver { _ in
			self.peeringController?.restartAdvertising()
		})

		notificationObservers.append(AccountControllerFactory.NotificationName.accountCreated.addObserver { _ in
			self.peeringController?.checkPeering { peering in
				guard peering else { return }

				self.peeringController?.startAdvertising(restartOnly: false)
			}
		})

		notificationObservers.append(AccountControllerFactory.NotificationName.accountDeleted.addObserver { _ in
			self.peeringController?.teardown()
		})

		notificationObservers.append(AccountController.NotificationName.unpinned.addAnyPeerObserver(pinStateChangeHandler))
		notificationObservers.append(AccountController.NotificationName.unmatch.addAnyPeerObserver(pinStateChangeHandler))

		notificationObservers.append(AccountController.NotificationName.pinMatch.addAnyPeerObserver { peerID, _ in
			ServerChatFactory.chat { sc in
				sc?.initiateChat(with: peerID)
			}
		})

		notificationObservers.append(PeeringController.Notifications.peerAppeared.addAnyPeerObserver { peerID, notification  in
			let dvs = self.discoveryViewState
			let svs = self.socialViewState

			if AppViewState.shared.isActive || dvs.browseFilter.displayFilteredPeople {
				self.peeringController?.loadAdditionalInfo(of: peerID, loadPortrait: true)
				return
			}

			guard let model = dvs.people[peerID],
				  let idModel = svs.people[peerID],
				  dvs.browseFilter.check(info: model.info, pinState: idModel.pinState) else { return }

			self.peeringController?.loadAdditionalInfo(of: peerID, loadPortrait: true)
		})
	}

	/// Observes notifications.
	private init() {
		observeNotifications()
	}

	/// All references to NotificationCenter observers by this object.
	private var notificationObservers: [Any] = []
}

// View states.
extension Mediator {
	var discoveryViewState: DiscoveryViewState { return DiscoveryViewState.shared }
	var socialViewState: SocialViewState { return SocialViewState.shared }
	var serverChatViewState: ServerChatViewState { return ServerChatViewState.shared }
	var inAppNotificationViewState: InAppNotificationStackViewState { return InAppNotificationStackViewState.shared }

	/// Displays `error` to the user. `title` and `furtherDescription` must be localized.
	func display(error: Error, title: String, furtherDescription: String? = nil) {
		let ianvs = inAppNotificationViewState
		DispatchQueue.main.async {
			ianvs.display(InAppNotification(localizedTitle: title, localizedMessage: error.localizedDescription, severity: .error, furtherDescription: nil))
		}
	}

	@MainActor
	func showOrMessage(_ peerID: PeerID) {
		if let serverChatPersona = serverChatViewState.people[peerID] {
			serverChatViewState.displayedPeerID = peerID
		} else if let discoveryPersona = discoveryViewState.people[peerID] {
			discoveryViewState.displayedPersona = discoveryPersona
		}
	}

	@MainActor
	func show(_ peerID: PeerID) {
		if let discoveryPersona = discoveryViewState.people[peerID] {
			discoveryViewState.displayedPersona = discoveryPersona
		}
	}
}


// MARK: - Server Chat

// MARK: ServerChatDelegate

extension Mediator: ServerChatDelegate {
	func decodingPersistedChatDataFailed(with error: Error) {
		self.display(error: error, title:NSLocalizedString( "Decoding Persisted Chat Data Failed", comment: "Title of alert."))
	}

	func encodingPersistedChatDataFailed(with error: Error) {
		self.display(error: error, title: NSLocalizedString("Encoding Persisted Chat Data Failed", comment: "Title of alert."))
	}

	func configurePusherFailed(_ error: Error) {
		self.display(error: error, title: NSLocalizedString("Push Notifications Unavailable", comment: "Title of alert."))
	}

	func cannotJoinRoom(_ error: Error) {
		self.display(error: error, title: NSLocalizedString("Cannot Join Room", comment: "Title of alert."))
	}

	func decryptionError(_ error: Error, peerID: PeerID, recreateRoom: @escaping @Sendable () -> Void) {
		let dvs = self.discoveryViewState
		DispatchQueue.main.async {
			let name = dvs.people[peerID]?.info.nickname ?? peerID.uuidString

			let alertTitle = NSLocalizedString("Broken Chatroom", comment: "Title of broken room alert")
			let alertBody = String(format: NSLocalizedString("broken_chatroom_content", comment: "Content of broken room alert."), name, error.localizedDescription)
			let recreateRoomButtonTitle = NSLocalizedString("Re-create room", comment: "Caption of button.")

			// TODO: ask user if they want to re-create the room
		}
	}

	func serverChatCertificateIsInvalid() {
		let error = createApplicationError(localizedDescription: NSLocalizedString("chat_server_cert_invalid", comment: "User-facing security error."))
		self.display(error: error, title: NSLocalizedString("Connection to Chat Server Failed", comment: "Error message title"))
	}

	func serverChatClosed(error: Error?) {
		let scvs = self.serverChatViewState
		DispatchQueue.main.async {
			scvs.clear()
		}

		error.map {
			self.display(error: $0, title: NSLocalizedString("Connection to Chat Server Lost", comment: "Error message title"))
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
	
	func shouldStopAdvertising(_ result: @escaping (Bool) -> ()) {
		// we need to invoke `result` on the same queue as in `advertiseData`.
		AccountControllerFactory.shared.use { _ in
			result(true)
		}
	}
	
	func cleanup(allPeers: [PeereeIdentity], _ result: @escaping ([PeerID]) -> ()) {
		AccountControllerFactory.shared.use({ ac in
			// never remove our own view model or the view model of pinned peers
			result(allPeers.filter { $0.peerID != ac.peerID && !ac.isPinned($0) }.map { $0.peerID })
		}, { error in
			error.map { flog(Self.LogTag, $0.localizedDescription) }
			result([])
		})
	}

	func advertiseData(_ result: @escaping (PeereeIdentity, KeyPair, PeerInfo, String, URL) -> ()) {
		let ds = self.discoveryViewState
		DispatchQueue.main.async {
			let info = ds.profile.info
			let bio = ds.profile.biography

			AccountControllerFactory.shared.use { ac in
				result(ac.identity, ac.keyPair, info, bio, UserPeer.pictureResourceURL)
			}
		}
	}

	func verify(_ peerID: PeerID, nonce: Data, signature: Data, _ result: @escaping (Bool) -> ()) {
		// we do not need this currently
		result(false)
//		AccountControllerFactory.shared.use { ac in
//			// we need to compute the verification in all cases, because if we would only do it if we have a public key available, it takes less time to fail if we did not pin the attacker -> timing attack: the attacker can deduce whether we pinned him, because he sees how much time it takes to fulfill their request
//			do {
//				let id = try ac.id(of: peerID)
//				try id.publicKey.verify(message: nonce, signature: signature)
//
//				// we need to check if we pin MATCHED the peer, because if we would sent him a successful authentication return code while he did not already pin us, it means he can see that we pinned him
//				result(ac.hasPinMatch(peerID))
//			} catch let exc {
//				elog(Self.LogTag, "A peer tried to authenticate to us as \(peerID). Message: \(exc.localizedDescription)")
//				result(false)
//			}
//		}
	}
}

// MARK: PeeringControllerDelegate
extension Mediator: PeeringControllerDelegate {
	func advertisingStopped(with error: Error) {
		self.display(error: error, title: NSLocalizedString("Bluetooth Publish Failed", comment: "Error title"))
	}

	func bluetoothNetwork(isAvailable: Bool) {
		self.peeringController?.change(peering: isAvailable)
	}

	func encodingPeersFailed(with error: Error) {
		self.display(error: error, title: NSLocalizedString("Encoding Recent Peers Failed", comment: "Low-level error"))
	}

	func decodingPeersFailed(with error: Error) {
		self.display(error: error, title: NSLocalizedString("Decoding Recent Peers Failed", comment: "Low-level error"))
	}
}

extension Mediator {

	/// Read-only access to persisted peers.
	public func readPeer(_ peerID: PeerID, _ completion: @escaping (Peer?) -> ()) {
		if let pc = self.peeringController {
			pc.readPeer(peerID, completion)
		} else {
			completion(nil)
		}
	}

	/// Toggle the bluetooth network between _on_ and _off_.
	func togglePeering(on: Bool) {
		let dvs = self.discoveryViewState

		/// Delayed setting of the PeeringController's delegate to avoid displaying the Bluetooth permission dialog at app start
		guard let pc = peeringController else {
			guard on else { return }

			// first time accessing Bluetooth
			// PeeringController.isBluetoothOn is `false` in all cases here!
			// Creating a PeeringController will trigger `bluetoothNetwork(isAvailable:)`, which will then automatically go online
			peeringController = PeeringController(viewModel: dvs, dataSource: self, delegate: self)

			return
		}

		DispatchQueue.main.async {
			if dvs.isBluetoothOn {
				pc.change(peering: on)

				Task {
					await HapticController.shared.playHapticPin()
				}
			} else {
				open(urlString: UIApplication.openSettingsURLString)
			}
		}
	}
}


// MARK: - Social Graph

extension Mediator {
	/// Sets up an `AccountController` after it was created; must be called on its `dQueue`.
	func setup(ac: AccountController, errorTitle: String) {
		let nm = self.notificationManager
		let dvs = self.discoveryViewState

		ac.delegate = self

		ac.refreshBlockedContent { error in
			let title = NSLocalizedString("Objectionable Content Refresh Failed", comment: "Title of alert when the remote API call to refresh objectionable portrait hashes failed.")
			let message = socialModuleErrorMessage(from: error)
			DispatchQueue.main.async {
				InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: title, localizedMessage: message, severity: .error, furtherDescription: nil))
			}
		}

		ServerChatFactory.initialize(ourPeerID: ac.peerID, dataSource: self) { factory in
			factory.delegate = self
			factory.conversationDelegate = self.serverChatViewState

			factory.setup { result in
				switch result {
				case .success(_):
					nm.setupNotifications()
				case .failure(let failure):
					DispatchQueue.main.async {
						let message = serverChatModuleErrorMessage(from: failure, on: dvs)
						InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: errorTitle, localizedMessage: message, severity: .error, furtherDescription: nil))
					}
				}
			}
		}
	}
}

// MARK: AccountControllerDelegate
extension Mediator: AccountControllerDelegate {
	func pin(of peerID: PeerID, failedWith error: Error) {
		self.display(error: error, title: NSLocalizedString("Pin Failed", comment: "Title of in-app error notification"))
	}

	func publicKeyMismatch(of peerID: PeerID) {
		let ianvs = self.inAppNotificationViewState
		let dvs = self.discoveryViewState
		DispatchQueue.main.async {
			let name = dvs.persona(of: peerID).info.nickname
			let message = String(format: NSLocalizedString("The identity of %@ is invalid.", comment: "Message of Possible Malicious Peer alert"), name)
			let error = createApplicationError(localizedDescription: message)
			ianvs.display(InAppNotification(localizedTitle: NSLocalizedString("Possible Malicious Peer", comment: "Title of public key mismatch in-app notification"), localizedMessage: error.localizedDescription, severity: .error, furtherDescription: nil))
		}
	}

	func sequenceNumberResetFailed(error: Error) {
		let ianvs = self.inAppNotificationViewState
		DispatchQueue.main.async {
			let message = socialModuleErrorMessage(from: error)
			let title = NSLocalizedString("Resetting Server Nonce Failed",
										  comment: "Title of sequence number reset failure alert")
			let description = NSLocalizedString("The server nonce is used to secure your connection.",
												comment: "Further description of Resetting Server Nonce Failed alert")
			ianvs.display(InAppNotification(localizedTitle: title, localizedMessage: message, severity: .error, furtherDescription: description))
		}
	}

	func sequenceNumberReset() {
		let ianvs = self.inAppNotificationViewState
		DispatchQueue.main.async {
			let message = NSLocalizedString("A request has failed, please try again.", comment: "Error body")
			let title = NSLocalizedString("Request Failed", comment: "Error title")
			ianvs.display(InAppNotification(localizedTitle: title, localizedMessage: message, severity: .error, furtherDescription: nil))
		}
	}
}

// MARK: SocialViewDelegate
extension Mediator: SocialViewDelegate {
	func createIdentity() {
		AccountControllerFactory.shared.createAccount { result in
			switch result {
			case .success(let ac):
				self.setup(ac: ac, errorTitle: NSLocalizedString("Chat Account Creation Failed", comment: "Error message title"))

			case .failure(let error):
				let title = NSLocalizedString("Account Creation Failed", comment: "Title of alert")
				let message = socialModuleErrorMessage(from: error)
				DispatchQueue.main.async {
					InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: title, localizedMessage: message, severity: .error, furtherDescription: NSLocalizedString("Please go to the bottom of your profile to try again.", comment: "Further description of account creation failure error")))
				}
			}
		}
	}

	func deleteIdentity() {
		self.togglePeering(on: false)

		// TODO: make this method atomic

		ServerChatFactory.use { f in
			f?.deleteAccount() { error in
				error.map { error in
					let title = NSLocalizedString("Chat Account Deletion Failed", comment: "Title of in-app alert.")
					DispatchQueue.main.async {
						let message = serverChatModuleErrorMessage(from: error, on: DiscoveryViewState.shared)
						InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: title, localizedMessage: message, severity: .error, furtherDescription: nil))
					}
				}
			}
		}

		AccountControllerFactory.shared.deleteAccount() { error in
			error.map { error in
				let title = NSLocalizedString("Connection Error", comment: "Standard title message of alert for internet connection errors.")
				let message = socialModuleErrorMessage(from: error)
				DispatchQueue.main.async {
					InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: title, localizedMessage: message, severity: .error, furtherDescription: nil))
				}
			}
		}
	}

	func pinToggle(peerID: PeerID) {
		DispatchQueue.main.async {
			self.pinToggleOnMain(peerID: peerID)
		}
	}

	@MainActor
	private func pinToggleOnMain(peerID: PeerID) {
		let socialPersona = self.socialViewState.persona(of: peerID)

		guard !socialPersona.pinState.isPinned else {
			AccountControllerFactory.shared.use { $0.updatePinStatus(of: socialPersona.id, force: true) }
			return
		}

		if !socialViewState.accountExists {
			let title = NSLocalizedString("Peeree Identity Required", comment: "Title of alert when the user wants to go online but lacks an account and it's creation failed.")
			let message = NSLocalizedString("Tap on 'Profile' to create your Peeree identity.", comment: "The user lacks a Peeree account")
			InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: title, localizedMessage: message, severity: .error, furtherDescription: nil))
		} else {
			self.readPeer(peerID) { peer in
				guard let id = peer?.id else { return }

				AccountControllerFactory.shared.use { $0.pin(id) }
			}

		}
	}

	func removePin(peerID: PeerID) {
		AccountControllerFactory.shared.use { $0.unpin(peerID) }
	}

	func reportPortrait(peerID: PeerID) {
		DispatchQueue.main.async {
			self.reportPortraitOnMain(peerID: peerID)
		}
	}

	@MainActor
	func reportPortraitOnMain(peerID: PeerID) {
		guard let discoveryPersona = self.discoveryViewState.people[peerID],
			 let portrait = discoveryPersona.cgPicture else { return }

		let hash = discoveryPersona.pictureHash
		AccountControllerFactory.shared.use { ac in
			ac.report(peerID: peerID, portrait: portrait, portraitHash: hash) { (error) in
				let message = socialModuleErrorMessage(from: error)
				DispatchQueue.main.async {
					let title = NSLocalizedString("Reporting Portrait Failed", comment: "Title of alert dialog")
					InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: title, localizedMessage: message, severity: .error, furtherDescription: nil))
				}
			}
		}
	}
}
