//
//  PeeringController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 04.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics

/// Handles all events specific to a single `PeerID`.
protocol PeeringDelegate {
	func loaded(biography: String)
	func loaded(picture: CGImage, hash: Data)
	func didRange(rssi: NSNumber?, error: Error?)
	func failedVerification(error: Error)
	func didVerify()
	func didRemoteVerify()
	func receivedPinMatchIndication()

	func received(message: String, at: Date)

	func indicatePinMatch()
}

/// Receiver of `PeeringController` events.
public protocol PeeringControllerDelegate {
	/// Advertising the Bluetooth service stopped ungracefully.
	func advertisingStopped(with error: Error)

	/// An error during the server chat login or account creation failed.
	func serverChatLoginFailed(with error: ServerChatError)

	/// A serialization error occurred.
	func encodingPeersFailed(with error: Error)

	/// A serialization error occurred.
	func decodingPeersFailed(with error: Error)

	/// All data was loaded.
	func peeringControllerIsReadyToGoOnline()
}

/// The PeeringController singleton is the app's interface to the bluetooth network as well as to information about stored peers.
public final class PeeringController : LocalPeerManagerDelegate, RemotePeerManagerDelegate, PersistedPeersControllerDelegate {
	// MARK: - Public and Internal

	// MARK: Classes, Structs, Enums

	/// Keys in the `userInfo` dict of a notification.
	public enum NotificationInfoKey: String {
		case again, connectionState
	}

	/// Names of notifications sent by `PeeringController`.
	public enum Notifications: String {
		case connectionChangedState
		case peerAppeared, peerDisappeared
		case persistedPeersLoadedFromDisk

		/// Post this case to the `NotificationCenter` on the main thread.
		fileprivate func post(_ peerID: PeerID? = nil, again: Bool? = nil) {
			var userInfo: [AnyHashable: Any]? = nil
			if let id = peerID {
				if let a = again {
					userInfo = [PeerID.NotificationInfoKey : id, NotificationInfoKey.again.rawValue : a]
				} else {
					userInfo = [PeerID.NotificationInfoKey : id]
				}
			}
			postAsNotification(object: PeeringController.shared, userInfo: userInfo)
		}
	}

	// MARK: Static Constants

	/// The singleton instance of this class.
	public static let shared = PeeringController()

	// MARK: Static Variables

	// MARK: Constants

	// MARK: Variables

	/// Hardware query.
	public var isBluetoothOn: Bool { return remotePeerManager.isBluetoothOn }

	/// Receives general updates and errors of the `PeeringController`.
	public var delegate: PeeringControllerDelegate? = nil

	/// Queries whether our Bluetooth service is 'online', meaning we are scanning and, if possible, advertising.
	public func checkPeering(_ callback: @escaping (Bool) -> Void) {
		remotePeerManager.checkIsScanning(callback)
	}

	/// Controls whether our Bluetooth service is 'online', meaning we are scanning and, if possible, advertising.
	public func change(peering newValue: Bool) {
		remotePeerManager.checkIsScanning { isScanning in
			guard newValue != isScanning else { return }

			if newValue {
				self.remotePeerManager.scan()
				self.startAdvertising(restartOnly: false)
			} else {
				self.stopAdvertising()
				self.remotePeerManager.stopScan()
			}

			self.connectionChangedState(newValue)
		}
	}

	/// Restart advertising if it is currently on, e.g. when the user peer data changed.
	func restartAdvertising() {
		startAdvertising(restartOnly: true)
	}

	// MARK: Methods

	/// Entry point for interactions with a peer coming from the server chat module of the app.
	func serverChatInteraction(with peerID: PeerID, completion: @escaping (ServerChatManager) -> ()) {
		withManager(of: peerID, completion: completion)
	}

	/// Entry point for interactions with a peer coming from the main module of the app.
	public func interact(with peerID: PeerID, completion: @escaping (PeerInteraction) -> ()) {
		withManager(of: peerID, completion: completion)
	}

	/// Starts the disk read process of loading the image of `peerID` from disk.
	public func loadPortraitFromDisk(of peerID: PeerID) {
		persistence.loadPortrait(of: peerID)
	}

	/// Retrieves the last read dates per `PeerID`.
	public func getLastReads(completion: @escaping ([PeerID : Date]) -> ()) {
		persistence.readLastReads(completion: completion)
	}

	/// Persists optional peer data.
	public func set(lastRead date: Date, of peerID: PeerID) {
		persistence.set(lastRead: date, of: peerID)
	}

	// MARK: LocalPeerManagerDelegate

	func advertisingStarted() {}

	func advertisingStopped(with error: Error?) {
		error.map { delegate?.advertisingStopped(with: $0) }
	}

	func authenticationFromPeerFailed(_ peerID: PeerID, with error: Error) {
		// ignored for now, since we do not rely on authentication via Bluetooth (was only necessary for messaging, which is not used anymore)
	}

	func characteristicSigningFailed(with error: Error) {
		stopAdvertising()
		delegate?.advertisingStopped(with: error)
	}

	func receivedPinMatchIndication(from peerID: PeerID) {
		manage(peerID) { manager in
			manager.receivedPinMatchIndication()
		}
	}

	func received(message: String, from peerID: PeerID) {
		manage(peerID) { manager in
			manager.received(message: message, at: Date())
		}
	}

	// MARK: RemotePeerManagerDelegate

	func remotePeerManagerIsReady() {
		delegate?.peeringControllerIsReadyToGoOnline()
	}

	func scanningStopped() {
		stopAdvertising()
		peerManagers.removeAll()
		connectionChangedState(false)
	}

	func peerAppeared(_ peer: Peer, again: Bool) {
		persistence.addPeers {
			return Set<Peer>([peer])
		}

		DispatchQueue.main.async {
			let now = Date()
			self.lastSeenDates[peer.id.peerID] = now
			archiveObjectInUserDefs(self.lastSeenDates as NSDictionary, forKey: PeeringController.LastSeenKey)

			Self.updateViewModels(of: peer, lastSeen: now)
			PeerViewModelController.modify(peerID: peer.id.peerID) { model in
				model.isAvailable = true
			}
			// make sure the notification is sent only after the view model is updated:
			Notifications.peerAppeared.post(peer.id.peerID, again: again)
		}

		manage(peer.id.peerID) { manager in
			// always send pin match indication on new connect to be absolutely sure that the other really got that
			manager.indicatePinMatch()
		}
	}

	func peerDisappeared(_ peerID: PeerID, cbPeerID: UUID) {
		localPeerManager?.disconnect(cbPeerID)

		DispatchQueue.main.async {
			let now = Date()
			self.lastSeenDates[peerID] = now
			archiveObjectInUserDefs(self.lastSeenDates as NSDictionary, forKey: PeeringController.LastSeenKey)
			PeerViewModelController.modify(peerID: peerID) { model in
				model.isAvailable = false
				model.lastSeen = now
			}
			Notifications.peerDisappeared.post(peerID)
		}
	}

	func loaded(picture: CGImage, of peer: Peer, hash: Data) {
		persistence.writeBlob(of: peer.id.peerID) { blob in
			blob.portrait = picture
		}

		obtained(picture, hash: hash, of: peer.id.peerID)
	}

	func loaded(biography: String, of peer: Peer) {
		persistence.writeBlob(of: peer.id.peerID) { blob in
			blob.biography = biography
		}
		manage(peer.id.peerID) { manager in
			manager.loaded(biography: biography)
		}
	}

	func didRange(_ peerID: PeerID, rssi: NSNumber?, error: Error?) {
		manage(peerID) { manager in
			manager.didRange(rssi: rssi, error: error)
		}
	}

	func failedVerification(of peerID: PeerID, error: Error) {
		manage(peerID) { manager in
			manager.failedVerification(error: error)
		}
	}

	func didVerify(_ peerID: PeerID) {
		manage(peerID) { manager in
			manager.didVerify()
		}
	}

	func didRemoteVerify(_ peerID: PeerID) {
		manage(peerID) { manager in
			manager.didRemoteVerify()
		}
	}

	// MARK: PersistedPeersControllerDelegate

	public func persistedPeersLoadedFromDisk(_ peers: Set<Peer>) {
		self.cleanupPersistedPeers()
		DispatchQueue.main.async {
			for peer in peers {
				Self.updateViewModels(of: peer, lastSeen: self.lastSeenDates[peer.id.peerID] ?? Date.distantPast)
			}
			Notifications.persistedPeersLoadedFromDisk.post()
		}
	}

	public func persistedBiosLoadedFromDisk(_ bios: [PeerID : String]) {
		DispatchQueue.main.async {
			for entry in bios {
				PeerViewModelController.modify(peerID: entry.key) { model in
					model.biography = entry.value
				}

				// TODO: We load all the portraits into memory for now. Later, we should only load them once a peer is displayed in browse or pin match table view.
				// and we begin loadding the portraits only after persistedBiosLoadedFromDisk(), since loading the bios currently may overwrite the images
				self.persistence.loadPortrait(of: entry.key)
			}
		}
	}

	public func persistedLastReadsLoadedFromDisk(_ lastReads: [PeerID : Date]) {
		// fix unread message count if last reads where read after server chat went online
		// PERFORMANCE: poor
		DispatchQueue.main.async {
			for (peerID, model) in PeerViewModelController.viewModels {
				guard let lastReadDate = lastReads[peerID] else { continue }

				var unreadCount = 0
				for transcript in model.transcripts {
					if transcript.timestamp > lastReadDate { unreadCount += 1 }
				}

				guard unreadCount != model.unreadMessages else { continue }

				PeerViewModelController.modify(peerID: peerID) { modifyModel in
					modifyModel.unreadMessages = unreadCount
				}
			}
		}
	}

	public func portraitLoadedFromDisk(_ portrait: CGImage, of peerID: PeerID, hash: Data) {
		obtained(portrait, hash: hash, of: peerID)
	}

	public func encodingFailed(with error: Error) {
		delegate?.encodingPeersFailed(with: error)
	}

	public func decodingFailed(with error: Error) {
		delegate?.decodingPeersFailed(with: error)
	}

	// MARK: - Private

	private init() {
		remotePeerManager.delegate = self
		persistence.delegate = self

		let nsLastSeenDates: NSDictionary? = unarchiveObjectFromUserDefs(PeeringController.LastSeenKey)

		DispatchQueue.main.async {
			self.lastSeenDates = nsLastSeenDates as? [PeerID : Date] ?? [PeerID : Date]()
		}

		observeNotifications()

		persistence.loadInitialData()
	}

	deinit {
		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	// MARK: Classes, Structs, Enums

	// MARK: Static Constants

	private static let LastSeenKey = "RecentPeersController.LastSeenKey"
	private static let MaxRememberedHours = 48

	// MARK: Static Methods

	/// Populates the current peer-related data to the view models; must be called on the main thread!
	private static func updateViewModels(of peer: Peer, lastSeen: Date) {
		let peerID = peer.id.peerID

		PeerViewModelController.update(peerID, info: peer.info, lastSeen: lastSeen)

		// This is a bit tricky. We can get the public key from both the AccountController and the PersistedPeersController.
		// For now, we always use the one from the AccountController.
		PeereeIdentityViewModelController.upsert(peerID: peerID, insert: PeereeIdentityViewModel(id: peer.id)) { model in
			// only insert if it wasn't already defined by AccountController
		}
	}

	// MARK: Constants

	/// Responsible for advertising the user's data; access only on `UserPeer`'s queue, e.g. through `UserPeer.read(on: nil)`.
	private var localPeerManager: LocalPeerManager? = nil
	private let remotePeerManager = RemotePeerManager()

	private let persistence = PersistedPeersController(filename: "peers.json", targetQueue: DispatchQueue(label: "de.peeree.PeeringController.persistence", qos: .utility))

	// MARK: Variables

	/// PeerManagers are the central interaction point with other peers.
	private var peerManagers = SynchronizedDictionary<PeerID, PeerManager>(queueLabel: "com.peeree.peerManagers", qos: .userInitiated)

	/// when was a specific PeerID last encountered via Bluetooth. Only access from main thread!
	private var lastSeenDates: [PeerID : Date] = [:]

	/// all references to NotificationCenter observers
	private var notificationObservers: [NSObjectProtocol] = []

	// MARK: Methods

	/// Starts advertising our data via Bluetooth.
	private func startAdvertising(restartOnly: Bool) {
		AccountController.use { ac in
			let keyPair = ac.keyPair
			// these values MAY arrive a little late, but that is very unlikely
			self.remotePeerManager.set(userPeerID: ac.peerID, keyPair: keyPair)

			UserPeer.instance.read(on: nil) { peerInfo, _, _, biography in
				guard (!restartOnly || self.localPeerManager != nil), let info = peerInfo else { return }

				self.localPeerManager?.stopAdvertising()

				let l = LocalPeerManager(peer: Peer(id: ac.identity, info: info),
										 biography: biography, keyPair: keyPair, pictureResourceURL: UserPeer.pictureResourceURL)
				self.localPeerManager = l
				l.delegate = self
				l.startAdvertising()
			}
		}
	}

	/// Stops advertising our data via Bluetooth.
	private func stopAdvertising() {
		UserPeer.instance.read(on: nil) { _, _, _, _ in
			self.localPeerManager?.stopAdvertising()
			self.localPeerManager = nil
		}
	}

	/// Interact with the `PeeringDelegate` interface of a `PeerManager` on their queue.
	private func manage(_ peerID: PeerID, completion: @escaping (PeeringDelegate) -> ()) {
		withManager(of: peerID, completion: completion)
	}

	/// Do not use this method directly. Use either interact() or manage()
	private func withManager(of peerID: PeerID, completion: @escaping (PeerManager) -> ()) {
		peerManagers.accessAsync { managers in
			if let manager = managers[peerID] {
				completion(manager)
			} else {
				let manager = PeerManager(peerID: peerID, remotePeerManager: self.remotePeerManager)
				managers[peerID] = manager
				completion(manager)
			}
		}
	}

	/// Performs additional logic when a picture was received, e.g. objectionable content checks.
	private func obtained(_ picture: CGImage, hash: Data, of peerID: PeerID) {
		self.manage(peerID) { manager in
			manager.loaded(picture: picture, hash: hash)
		}
	}

	/// Remove peers from disk which haven't been seen for `MaxRememberedHours` and are not pin matched.
	private func cleanupPersistedPeers() {
		DispatchQueue.main.async {
			let lastSeens = self.lastSeenDates

			self.persistence.readPeers { peers in
				AccountController.use { ac in
					self.performCleanup(allPeers: peers, lastSeens: lastSeens, accountController: ac)
				}
			}
		}
	}

	/// Cleans unnecessary peers from disk; must be called on AccountController.dQueue!
	private func performCleanup(allPeers: Set<Peer>, lastSeens: [PeerID: Date], accountController: AccountController) {
		let now = Date()
		let never = Date.distantPast
		let cal = Calendar.current as NSCalendar

		let removePeers = allPeers.filter { peer in
			// never remove our own view model or the view model of pinned peers
			guard peer.id.peerID != accountController.peerID && !accountController.isPinned(peer.id) else { return false }

			let lastSeenAgoCalc = cal.components(NSCalendar.Unit.hour, from: lastSeens[peer.id.peerID] ?? never, to: now, options: []).hour
			let lastSeenAgo = lastSeenAgoCalc ?? PeeringController.MaxRememberedHours + 1
			return lastSeenAgo > PeeringController.MaxRememberedHours
		}

		self.peerManagers.accessAsync { mgrs in
			for peer in removePeers {
				mgrs.removeValue(forKey: peer.id.peerID)
			}
		}

		persistence.removePeers(removePeers)
	}

	/// Observes relevant notifications in `NotificationCenter`.
	private func observeNotifications() {
		notificationObservers.append(AccountController.NotificationName.pinMatch.addAnyPeerObserver { peerID, _ in
			self.manage(peerID) { manager in
				manager.indicatePinMatch()
			}
		})
		notificationObservers.append(AccountController.NotificationName.accountCreated.addObserver { _ in
			self.checkPeering { peering in
				guard peering else { return }

				AccountController.use { ac in
					self.remotePeerManager.set(userPeerID: ac.peerID, keyPair: ac.keyPair)
					self.startAdvertising(restartOnly: false)
				}
			}
		})
		notificationObservers.append(AccountController.NotificationName.accountDeleted.addObserver { _ in
			self.remotePeerManager.set(userPeerID: nil, keyPair: nil)
			// delete all cached pictures and finally the persisted PeerInfo records themselves
			self.persistence.clear()
			self.peerManagers.removeAll()
			PeerViewModelController.clear()
		})

		notificationObservers.append(UserPeer.NotificationName.changed.addObserver { _ in
			self.restartAdvertising()
		})
	}

	/// Posts `connectionChangedState` notification and starts/stops the server chat module.
	private func connectionChangedState(_ newState: Bool) {
		DispatchQueue.main.async { PeerViewModelController.peering = newState }
		Notifications.connectionChangedState.postAsNotification(object: self, userInfo: [NotificationInfoKey.connectionState.rawValue : NSNumber(value: newState)])

		if newState {
			ServerChatFactory.getOrSetupInstance { result in
				switch result {
				case .failure(let error):
					switch error {
					case .identityMissing:
						break
					default:
						self.delegate?.serverChatLoginFailed(with: error)
					}
				case .success(_):
					break
				}
			}
		} else {
			// we stay connected: ServerChatFactory.close()
		}
	}
}
