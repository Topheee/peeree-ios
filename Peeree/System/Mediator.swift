//
//  Mediator.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.04.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

// Platform Dependencies
import CoreGraphics
import UIKit
import Combine

// Internal Dependencies
import PeereeCore
import PeereeServerChat
import PeereeDiscovery
import PeereeIdP
import PeereeSocial

// External Dependencies
import KeychainWrapper

/// This singleton ties all Peeree modules together.
@MainActor
final class Mediator {

	// Log tag.
	private static let LogTag = "Mediator"

	/// Task holding notification observers.
	private var notificationTask: Task<Void, Never>?

	private let notificationManager = NotificationManager()

	private let accountControllerFactory: AccountControllerFactory

	private let socialController: SocialNetworkController

	private var serverChatFactory: ServerChatFactory?

	let appViewState = AppViewState()

	let discoveryViewState = DiscoveryViewState()

	let socialViewState = SocialViewState()

	let serverChatViewState = ServerChatViewState()

	private var peeringController: PeeringController?

	private func restartAdvertising() async throws {
		guard let pc = self.peeringController else { return }
		try await pc.restartAdvertising()
	}

	private func startAdvertising() async {
		guard let pc = self.peeringController else { return }

		guard await pc.checkPeering() else { return }

		Task {
			// TODO: error handling
			try await pc.startAdvertising(restartOnly: false)
		}
	}

	private func teardown() {
		self.peeringController?.teardown()
	}

	/// Observes relevant notifications in `NotificationCenter`.
	private nonisolated func observeNotifications() -> Task<Void, Never> {
		let scvs = self.serverChatViewState

		let pinStateChangeHandler: @Sendable (PeerID) -> Void = { peerID in
			Task {
				await self.serverChatFactory?.chat()?.leaveChat(with: peerID)
			}

			Task { @MainActor in
				scvs.matchedPeople.removeAll { $0.peerID == peerID }
			}
		}

		return Task {
			await withTaskGroup(of: Void.self) { taskGroup in

				let notificationCenter = NotificationCenter.default

				taskGroup.addTask {
					for await _ in notificationCenter
						.notifications(named: Notification.Name.userPeerChanged)
						.map ({ notification in
							return false
						}) {
						// TODO: error handling
						try? await self.restartAdvertising()
					}
				}

				taskGroup.addTask {
					for await _ in notificationCenter
						.notifications(named: Notification.Name.accountCreated)
						.map ({ notification in
							return false
						}) {
						await self.startAdvertising()
					}
				}

				taskGroup.addTask {
					for await _ in notificationCenter
						.notifications(named: Notification.Name.accountDeleted)
						.map ({ notification in
							return false
						}) {
						await self.teardown()
					}
				}

				taskGroup.addTask {
					for await (peerID, _) in Notification.Name.unpinned
						.observe(transform: { notification in
							return false
						}) {
						pinStateChangeHandler(peerID)
					}
				}

				taskGroup.addTask {
					for await (peerID, _) in Notification.Name.unmatch
						.observe(transform: { notification in
							return false
						}) {
						pinStateChangeHandler(peerID)
					}
				}

				taskGroup.addTask {
					for await (peerID, _) in Notification.Name.pinMatch
						.observe(transform: { notification in
							return false
						}) {
						await self.pinMatchOccured(peerID)
					}
				}

				taskGroup.addTask {
					for await (peerID, again) in Notification.Name.peerAppeared
						.observe(transform: { notification in
							return notification.userInfo?[PeeringController.NotificationInfoKey.again.rawValue] as? Bool ?? false
						}) {
						let sc = await self.serverChatFactory?.chat()
						await sc?.initiateChat(with: peerID)
						await self.peerAppeared(peerID, again: again)
					}
				}

				taskGroup.addTask {
					for await (peerID, message) in Notification.Name.serverChatMessageReceived
						.observe(transform: { notification in
							return notification.userInfo?[ServerChatViewState.NotificationInfoKey.message.rawValue] as? String
						}) {
						await self.received(message: message ?? "", from: peerID)
					}
				}

				// waits forever or cancellation
				for await _ in taskGroup {}
			}
		}
	}

	private func received(message: String, from peerID: PeerID) {
		let name = discoveryViewState.people[peerID]?.info.nickname ?? peerID.uuidString

		let title: String
		if #available(iOS 10.0, *) {
			// The localizedUserNotificationString(forKey:arguments:) method delays the loading of the localized string until the notification is delivered. Thus, if the user changes language settings before a notification is delivered, the alert text is updated to the user’s current language instead of the language that was set when the notification was scheduled.
			title = NSString.localizedUserNotificationString(forKey: "Message from %@.", arguments: [name])
		} else {
			let titleFormat = NSLocalizedString("Message from %@.", comment: "Notification alert body when a message is received.")
			title = String(format: titleFormat, name)
		}

		let messagesNotVisible = self.serverChatViewState.displayedPeerID != peerID

		guard messagesNotVisible || !self.appViewState.isActive else { return }

		NotificationManager.displayPeerRelatedNotification(
			title: title, body: message, peerID: peerID, category: .message)
	}

	private func peerAppeared(_ peerID: PeerID, again: Bool) {
		guard !again, let model = discoveryViewState.people[peerID],
			  let idModel = socialViewState.people[peerID],
			  discoveryViewState.browseFilter.check(info: model.info, pinState: idModel.pinState) else { return }

		let alertBodyFormat = NSLocalizedString("Found %@.", comment: "Notification alert body when a new peer was found on the network.")

		let category: NotificationManager.NotificationCategory =
			idModel.pinState == .pinMatch ? .none : .peerAppeared

		NotificationManager.displayPeerRelatedNotification(
			title: String(format: alertBodyFormat, model.info.nickname),
			body: "", peerID: peerID, category: category)
	}

	private func pinMatchOccured(_ peerID: PeerID) {
		Task {
			let sc = await self.serverChatFactory?.chat()
			await sc?.initiateChat(with: peerID)
		}

		if self.appViewState.isActive {
			// this will show pin match animation
			self.show(peerID)
		} else {
			let title = NSLocalizedString("New Pin Match!", comment: "Notification alert title when a pin match occured.")
			let alertBodyFormat = NSLocalizedString("Pin Match with %@!", comment: "Notification alert body when a pin match occured.")
			let alertBody = String(format: alertBodyFormat, discoveryViewState.people[peerID]?.info.nickname ?? peerID.uuidString)

			NotificationManager.displayPeerRelatedNotification(
				title: title, body: alertBody, peerID: peerID,
				category: .pinMatch)
		}
	}

	private func load(_ peerID: PeerID) {
		self.peeringController?.loadAdditionalInfo(of: peerID, loadPortrait: true)
	}

	private func peerAppeared(_ peerID: PeerID) {
		let dvs = self.discoveryViewState
		let svs = self.socialViewState

		if self.appViewState.isActive || dvs.browseFilter.displayFilteredPeople {
			self.load(peerID)
			return
		}

		guard let model = dvs.people[peerID],
			  let idModel = svs.people[peerID],
			  dvs.browseFilter.check(info: model.info, pinState: idModel.pinState) else { return }

		self.load(peerID)
	}

	init() {
		accountControllerFactory = .init(viewModel: socialViewState)
		socialController = SocialNetworkController(
			authenticator: accountControllerFactory,
			viewModel: socialViewState)
	}

	/// Run this on application startup.
	func start() async throws {
		Task { @MainActor in
			self.socialViewState.delegate = self
		}

		if notificationTask == nil {
			notificationTask = observeNotifications()
		}

		// start Bluetooth and server chat, but only if account exists
		if let ac = try await self.accountControllerFactory.use() {
			try await self.setup(ac: ac, errorTitle: NSLocalizedString(
				"Login to Chat Server Failed", comment: "Error message title"))
			try await self.togglePeering(on: true)
		}

		try await self.discoveryViewState.load()
	}

	/// Call this method on `applicationWillTerminate`.
	func stop() {
		Task {
			await self.serverChatFactory?.closeServerChat()
			try? await self.togglePeering(on: false)
		}
	}

	func configureRemoteNotifications(deviceToken: Data) {
		Task {
			await self.serverChatFactory?
				.configureRemoteNotificationsDeviceToken(deviceToken)
		}
	}

	func applicationDidReceiveMemoryWarning() {
		Task {
			try? await self.togglePeering(on: false)
		}
	}
}

// View states.
extension Mediator {

	/// Displays `error` to the user. `title` and `furtherDescription` must be localized.
	func display(error: Error, title: String, furtherDescription: String? = nil) {
		Task { @MainActor in
			InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: title, localizedMessage: error.localizedDescription, severity: .error, furtherDescription: nil))
		}
	}

	@MainActor
	func showOrMessage(_ peerID: PeerID) {
		if serverChatViewState.people[peerID] != nil {
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

	func serverChatCertificateIsInvalid() {
		let error = createApplicationError(localizedDescription: NSLocalizedString("chat_server_cert_invalid", comment: "User-facing security error."))
		self.display(error: error, title: NSLocalizedString("Connection to Chat Server Failed", comment: "Error message title"))
	}

	func serverChatClosed(error: Error?) {
		let scvs = self.serverChatViewState
		Task { @MainActor in
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

	func hasPinMatch(with peerID: PeerID, forceCheck: Bool) async throws -> Bool {
		let id = try await socialController.id(of: peerID)
		return try await socialController.updatePinStatus(of: id, force: forceCheck) == .pinMatch
	}

	/// Queries for all pin-matched peers.
	func pinMatches() async -> Set<PeerID> {
		return await socialController.pinMatches
	}
}


// MARK: - Discovery


// MARK: PeeringControllerDataSource
extension Mediator: PeeringControllerDataSource {

	func cleanup(allPeers: [PeereeIdentity]) async -> [PeerID] {
		// never remove our own view model or the view model of pinned peers
		return await socialController.unpinnedPeers(allPeers)
	}

	func advertiseData() async throws -> (PeerID, KeyPair, PeerInfo, String, URL) {
		let ds = self.discoveryViewState
		let info = ds.profile.info
		let bio = ds.profile.biography

		guard let ac = try await accountControllerFactory.use() else {
			throw unexpectedNilError()
		}

		return (await ac.peerID, await ac.keyPair, info, bio, UserPeer.pictureResourceURL)
	}
}

// MARK: PeeringControllerDelegate
extension Mediator: PeeringControllerDelegate {
	func advertisingStopped(with error: Error) {
		self.display(error: error, title: NSLocalizedString("Bluetooth Publish Failed", comment: "Error title"))
	}

	func bluetoothNetwork(isAvailable: Bool) {
		guard peeringController != nil else { return }
		Task {
			await go(peering: isAvailable)
		}
	}

	func encodingPeersFailed(with error: Error) {
		self.display(error: error, title: NSLocalizedString("Encoding Recent Peers Failed", comment: "Low-level error"))
	}

	func decodingPeersFailed(with error: Error) {
		self.display(error: error, title: NSLocalizedString("Decoding Recent Peers Failed", comment: "Low-level error"))
	}
}

extension Mediator {

	/// Turn `PeeringController` on or off.
	@MainActor
	func go(peering: Bool) async {
		guard let pc = peeringController else { return }

		do {
			let fb = UIImpactFeedbackGenerator()
			fb.prepare()

			try await pc.change(peering: peering)

			fb.impactOccurred()
		} catch {
			UINotificationFeedbackGenerator()
				.notificationOccurred(.error)

			let title = NSLocalizedString(
				"Going Online Failed",
				comment: "Low-level error")

			self.display(error: error, title: title)
		}
	}

	/// Read-only access to persisted peers.
	func readPeer(_ peerID: PeerID) async -> Peer? {
		return await self.peeringController?.readPeer(peerID)
	}

	/// Toggle the bluetooth network between _on_ and _off_.
	func togglePeering(on: Bool) async throws {
		let dvs = self.discoveryViewState

		/// Delayed setting of the PeeringController's delegate to avoid displaying the Bluetooth permission dialog at app start
		guard peeringController != nil else {
			guard on else { return }

			// first time accessing Bluetooth
			// PeeringController.isBluetoothOn is `false` in all cases here!
			// Creating a PeeringController will trigger `bluetoothNetwork(isAvailable:)`, which will then automatically go online
			let newPC = PeeringController(viewModel: dvs, dataSource: self, delegate: self)
			try await newPC.initialize()

			peeringController = newPC

			return
		}

		Task { @MainActor in
			if dvs.isBluetoothOn {
				await go(peering: on)
			} else {
				open(urlString: UIApplication.openSettingsURLString)
			}
		}
	}
}


// MARK: - Social Graph

extension Mediator {
	/// Sets up an `AccountController` after it was created.
	private func setup(ac: AccountController, errorTitle: String) async throws {
		let nm = self.notificationManager
		let dvs = self.discoveryViewState

		do {
			try await socialController.refreshBlockedContent()
		} catch {
			let title = NSLocalizedString("Objectionable Content Refresh Failed", comment: "Title of alert when the remote API call to refresh objectionable portrait hashes failed.")
			let message = socialModuleErrorMessage(from: error)
			Task { @MainActor in
				InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: title, localizedMessage: message, severity: .error, furtherDescription: nil))
			}
		}

		let factory = await ServerChatFactory(
			ourPeerID: ac.peerID, delegate: self,
			conversationDelegate: self.serverChatViewState)
		self.serverChatFactory = factory

		do {
			let sc = try await factory.use(onlyLogin: false, dataSource: self)
			self.serverChatViewState.backend = sc
			nm.setupNotifications(mediator: self)
		} catch {
			if let scError = error as? ServerChatError {
				let message = serverChatModuleErrorMessage(from: scError, on: dvs)
				InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: errorTitle, localizedMessage: message, severity: .error, furtherDescription: nil))
			} else {
				self.display(error: error, title: errorTitle)
			}
		}
	}
}

// MARK: SocialViewDelegate
extension Mediator: SocialViewDelegate {
	func createIdentity() {
		Task { await self.createIdentityAsync() }
	}

	private func createIdentityAsync() async {
		do {
			let ac = try await accountControllerFactory.createAccount()

			let title = NSLocalizedString("Chat Account Creation Failed",
										  comment: "Error message title")

			try await self.setup(ac: ac, errorTitle: title)
		} catch {
			let title = NSLocalizedString("Account Creation Failed",
										  comment: "Title of alert")
			let message = socialModuleErrorMessage(from: error)
			Task { @MainActor in
				let desc = NSLocalizedString("Please go to the bottom of your profile to try again.", comment: "Further description of account creation failure error")

				InAppNotificationStackViewState.shared.display(
					InAppNotification(localizedTitle: title,
									  localizedMessage: message,
									  severity: .error,
									  furtherDescription: desc))
			}
		}
	}

	func deleteIdentity() {
		Task { await self.deleteIdentityAsync() }
	}

	private func deleteIdentityAsync() async {
		do {
			try await self.togglePeering(on: false)

			if let f = self.serverChatFactory {
				do {
					try await f.deleteAccount()
				} catch let error as ServerChatError {
					let title = NSLocalizedString(
					 "Chat Account Deletion Failed",
					 comment: "Title of in-app alert.")

					let message = serverChatModuleErrorMessage(
						from: error, on: self.discoveryViewState)
					InAppNotificationStackViewState.shared.display(
						InAppNotification(
							localizedTitle: title, localizedMessage: message,
							severity: .error, furtherDescription: nil))
				}
			}

			try await accountControllerFactory.deleteAccount()

			await socialController.clearLocalData()
		} catch {
			let title = NSLocalizedString("Connection Error", comment: "Standard title message of alert for internet connection errors.")
			let message = socialModuleErrorMessage(from: error)
			Task { @MainActor in
				InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: title, localizedMessage: message, severity: .error, furtherDescription: nil))
			}
		}
	}

	func pinToggle(peerID: PeerID) {
		Task { await self.pinToggleOnMain(peerID: peerID) }
	}

	private func pinToggleOnMain(peerID: PeerID) async {
		let socialPersona = self.socialViewState.persona(of: peerID)

		do {
			guard !socialPersona.pinState.isPinned else {
				let peerID = try await socialController.id(of: socialPersona.id)
				_ = try await socialController.updatePinStatus(of: peerID, force: true)
				return
			}

			if socialViewState.accountExists != .on {
				let title = NSLocalizedString("Peeree Identity Required", comment: "Title of alert when the user wants to go online but lacks an account and it's creation failed.")
				let message = NSLocalizedString("Tap on 'Profile' to create your Peeree identity.", comment: "The user lacks a Peeree account")
				InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: title, localizedMessage: message, severity: .error, furtherDescription: nil))
			} else {
				let peer = await self.readPeer(peerID)
				guard let id = peer?.id else { return }

				try await socialController.pin(id)
			}
		} catch {
			InAppNotificationStackViewState.shared.display(genericError: error)
		}
	}

	func removePin(peerID: PeerID) {
		Task { await self.removePinAsync(peerID: peerID) }
	}

	private func removePinAsync(peerID: PeerID) async {
		do {
			try await socialController.unpin(peerID)
		} catch {
			InAppNotificationStackViewState.shared.display(genericError: error)
		}
	}

	func reportPortrait(peerID: PeerID) {
		Task { await self.reportPortraitAsync(peerID: peerID) }
	}

	private func reportPortraitAsync(peerID: PeerID) async {
		await self.reportPortraitOnMain(peerID: peerID)
	}

	private func reportPortraitOnMain(peerID: PeerID) async {
		guard let discoveryPersona = self.discoveryViewState.people[peerID],
			 let portrait = discoveryPersona.cgPicture else { return }

		do {
			let hash = discoveryPersona.pictureHash
			// TODO: hash signature
			try await socialController.report(peerID: peerID, portrait: portrait, portraitHash: hash, hashSignature: Data())
		} catch {
			let message = socialModuleErrorMessage(from: error)
			Task { @MainActor in
				let title = NSLocalizedString("Reporting Portrait Failed", comment: "Title of alert dialog")
				InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: title, localizedMessage: message, severity: .error, furtherDescription: nil))
			}
		}
	}
}
