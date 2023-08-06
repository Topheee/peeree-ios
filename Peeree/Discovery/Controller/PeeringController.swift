//
//  PeeringController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 04.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics
import KeychainWrapper
import PeereeCore

/// An approximisation of the distance to the peer's phone.
public enum PeerDistance {
	case unknown, close, nearby, far
}

/// Main information provider for the PeereeDiscovery module.
public protocol PeeringControllerDataSource {
	/// Obtains our identity, s.t. we are able to authenticate ourselves to others.
	func getIdentity(_ result: @escaping (PeereeIdentity, KeyPair) -> ())

	/// Verify the integrity of the `nonce`, using the `signature` and the peer's public key.
	func verify(_ peerID: PeerID, nonce: Data, signature: Data, _ result: @escaping (Bool) -> ())

	/// Asks for a list of `PeerID`s which can be safely removed from disk.
	func cleanup(allPeers: [PeereeIdentity], _ result: @escaping ([PeerID]) -> ())
}

/// Receiver of `PeeringController` events.
public protocol PeeringControllerDelegate {
	/// Advertising the Bluetooth service stopped ungracefully.
	func advertisingStopped(with error: Error)

	/// A serialization error occurred.
	func encodingPeersFailed(with error: Error)

	/// A serialization error occurred.
	func decodingPeersFailed(with error: Error)

	/// If `isAvailable`, you might call `PeeringController.shared.change(peering: true)`.
	func bluetoothNetwork(isAvailable: Bool)
}

/// The PeeringController singleton is the app's interface to the bluetooth network as well as to information about stored peers.
public final class PeeringController : LocalPeerManagerDelegate, DiscoveryManagerDelegate, PersistedPeersControllerDelegate {
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
	///
	/// > Note: Accessing this lazily instantiates the object (as is done with all static constants). Avoid automatic access at very first launch to not trigger the Bluetooth permission dialog too early.
	public static let shared = PeeringController()

	// MARK: Static Variables

	// MARK: Constants

	// MARK: Variables

	public var dataSource: PeeringControllerDataSource? = nil

	/// Receives general updates and errors of the `PeeringController`.
	public var delegate: PeeringControllerDelegate? = nil

	// MARK: Methods

	/// Queries whether our Bluetooth service is 'online', meaning we are scanning and, if possible, advertising.
	public func checkPeering(_ callback: @escaping (Bool) -> Void) {
		discoveryManager.checkIsScanning(callback)
	}

	/// Controls whether our Bluetooth service is 'online', meaning we are scanning and, if possible, advertising.
	public func change(peering newValue: Bool) {
		discoveryManager.checkIsScanning { isScanning in
			guard newValue != isScanning else { return }

			if newValue {
				self.discoveryManager.scan()
				self.startAdvertising(restartOnly: false)
			} else {
				self.stopAdvertising()
				self.discoveryManager.stopScan()
			}

			self.connectionChangedState(newValue)
		}
	}

	/// Restart advertising if it is currently on, e.g. when the user peer data changed.
	func restartAdvertising() {
		startAdvertising(restartOnly: true)
	}

	/// Stop all peering activity.
	public func teardown() {
		discoveryManager.set(userPeerID: nil, keyPair: nil)
		// delete all cached pictures and finally the persisted PeerInfo records themselves
		persistence.clear()
		DispatchQueue.main.async { self.viewModel.clear() }
	}

	/// Starts the disk read process of loading the image of `peerID` from disk.
	public func loadPortraitFromDisk(of peerID: PeerID) {
		persistence.loadPortrait(of: peerID)
	}

	/// Load Bio and optionally the portrait of a peer.
	public func loadAdditionalInfo(of peerID: PeerID, loadPortrait: Bool) {
		discoveryManager.loadAdditionalInfo(of: peerID, loadPortrait: loadPortrait)
	}

	/// Begin periodically measuring the distance to a peer.
	public func range(_ peerID: PeerID, _ block: @escaping (PeerID, PeerDistance) -> Void) {
		rangeBlock = block
		rangePeerID = peerID
		discoveryManager.range(peerID)
	}

	/// Stop the measurement.
	public func stopRanging() {
		rangeBlock = nil
		rangePeerID = nil
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
		// ignored
	}

	func verify(_ peerID: PeerID, nonce: Data, signature: Data, _ result: @escaping (Bool) -> ()) {
		dataSource?.verify(peerID, nonce: nonce, signature: signature, result)
	}

	// MARK: DiscoveryManagerDelegate

	func beganLoadingPortrait(_ progress: Progress, of peerID: PeereeCore.PeerID) {
		publish(to: peerID) { model in
			model.pictureProgress = progress
		}
	}

	func peerDiscoveryFinished(peerLastChangedDate: Date, of peerID: PeereeCore.PeerID) {
		self.discoveryManager.discoveryCompleted(of: peerID, lastChanged: peerLastChangedDate)
		self.discoveryManager.closeConnection(with: peerID)
	}

	func peerDiscoveryFailed(_ error: Error) {
		wlog("peer discovery failed: \(error)")
	}

	func discoveryManager(isReady: Bool) {
		DispatchQueue.main.async {
			self.viewModel.isBluetoothOn = isReady
			self.delegate?.bluetoothNetwork(isAvailable: isReady)
		}
	}

	func scanningStopped() {
		stopAdvertising()
		connectionChangedState(false)
	}

	func peerAppearedAgain(_ peerID: PeerID) {
		DispatchQueue.main.async {
			let now = Date()
			self.lastSeenDates[peerID] = now
			archiveObjectInUserDefs(self.lastSeenDates as NSDictionary, forKey: PeeringController.LastSeenKey)

			self.viewModel.modify(peerID: peerID) { model in
				model.isAvailable = true
			}

			// make sure the notification is sent only after the view model is updated:
			Notifications.peerAppeared.post(peerID, again: true)
		}
	}

	func peerDisappeared(_ peerID: PeerID, cbPeerID: UUID) {
		localPeerManager?.disconnect(cbPeerID)

		DispatchQueue.main.async {
			let now = Date()
			self.lastSeenDates[peerID] = now
			archiveObjectInUserDefs(self.lastSeenDates as NSDictionary, forKey: PeeringController.LastSeenKey)
			self.viewModel.modify(peerID: peerID) { model in
				model.isAvailable = false
				model.lastSeen = now
			}
			Notifications.peerDisappeared.post(peerID)
		}
	}

	func loaded(info: PeerInfo, of identity: PeereeIdentity) {
		let peer = Peer(id: identity, info: info)

		persistence.addPeers {
			return Set<Peer>([peer])
		}

		DispatchQueue.main.async {
			let now = Date()
			self.lastSeenDates[identity.peerID] = now
			archiveObjectInUserDefs(self.lastSeenDates as NSDictionary, forKey: PeeringController.LastSeenKey)
			Self.updateViewModels(of: peer, lastSeen: now)

			self.viewModel.modify(peerID: identity.peerID) { model in
				model.isAvailable = true
			}

			Notifications.peerAppeared.post(identity.peerID, again: false)
		}
	}

	func loaded(picture: CGImage, of peerID: PeereeCore.PeerID, hash: Data) {
		persistence.writeBlob(of: peerID) { blob in
			blob.portrait = picture
		}

		obtained(picture, hash: hash, of: peerID)
	}

	func loaded(biography: String, of peerID: PeereeCore.PeerID) {
		persistence.writeBlob(of: peerID) { blob in
			blob.biography = biography
		}

		publish(to: peerID) { model in
			model.biography = biography
		}
	}

	func didRange(_ peerID: PeerID, rssi: NSNumber?, error: Error?) {
		guard error == nil else {
			elog("Error updating range: \(error!.localizedDescription)")
			rerange(timeInterval: 7.0, tolerance: 2.5, distance: .unknown)
			return
		}
		switch rssi!.intValue {
		case -60 ... Int.max:
			rerange(timeInterval: 3.0, tolerance: 1.0, distance: .close)
		case -80 ... -60:
			rerange(timeInterval: 4.0, tolerance: 1.5, distance: .nearby)
		case -100 ... -80:
			rerange(timeInterval: 5.0, tolerance: 2.0, distance: .far)
		default:
			rerange(timeInterval: 7.0, tolerance: 2.5, distance: .unknown)
		}
	}

	func verified(_ peereeIdentity: PeereeCore.PeereeIdentity) {
		publish(to: peereeIdentity.peerID) { model in
			model.verified = true
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
				self.viewModel.modify(peerID: entry.key) { model in
					model.biography = entry.value
				}

				// TODO: We load all the portraits into memory for now. Later, we should only load them once a peer is displayed in browse or pin match table view.
				// and we begin loadding the portraits only after persistedBiosLoadedFromDisk(), since loading the bios currently may overwrite the images
				self.persistence.loadPortrait(of: entry.key)
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
		discoveryManager.delegate = self
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

		PeerViewModelController.shared.update(peerID, info: peer.info, lastSeen: lastSeen)

		// This is a bit tricky. We can get the public key from both the AccountController and the PersistedPeersController.
		// For now, we always use the one from the AccountController.
		PeereeIdentityViewModelController.upsert(peerID: peerID, insert: PeereeIdentityViewModel(id: peer.id)) { model in
			// only insert if it wasn't already defined by AccountController
		}
	}

	// MARK: Constants

	/// Responsible for advertising the user's data; access only on `UserPeer`'s queue, e.g. through `UserPeer.read(on: nil)`.
	private var localPeerManager: LocalPeerManager? = nil
	private let discoveryManager = DiscoveryManager()

	private let persistence = PersistedPeersController(filename: "peers.json", targetQueue: DispatchQueue(label: "de.peeree.PeeringController.persistence", qos: .utility))

	// Shortcut to `PeerViewModelController.shared`.
	private let viewModel = PeerViewModelController.shared

	// MARK: Variables

	/// when was a specific PeerID last encountered via Bluetooth. Only access from main thread!
	private var lastSeenDates: [PeerID : Date] = [:]

	/// all references to NotificationCenter observers
	private var notificationObservers: [NSObjectProtocol] = []

	// MARK: Methods

	/// Starts advertising our data via Bluetooth.
	public func startAdvertising(restartOnly: Bool) {
		dataSource?.getIdentity { identity, keyPair in
			// these values MAY arrive a little late, but that is very unlikely
			self.discoveryManager.set(userPeerID: identity.peerID, keyPair: keyPair)

			UserPeer.instance.read(on: nil) { peerInfo, _, _, biography in
				guard (!restartOnly || self.localPeerManager != nil), let info = peerInfo else { return }

				self.localPeerManager?.stopAdvertising()

				let l = LocalPeerManager(peer: Peer(id: identity, info: info),
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

	/// publish changes to the model on the main thread
	private func publish(to peerID: PeerID, completion: @escaping (inout PeerViewModel) -> ()) {
		DispatchQueue.main.async {
			PeerViewModelController.shared.modify(peerID: peerID, modifier: completion)
		}
	}

	/// Performs additional logic when a picture was received, e.g. objectionable content checks.
	private func obtained(_ picture: CGImage, hash: Data, of peerID: PeerID) {
		self.publish(to: peerID) { model in
			model.loaded(portrait: picture, hash: hash)
		}
	}

	/// Remove peers from disk which haven't been seen for `MaxRememberedHours` and are not pin matched.
	private func cleanupPersistedPeers() {
		DispatchQueue.main.async {
			let lastSeens = self.lastSeenDates

			self.persistence.readPeers { peers in
				self.performCleanup(allPeers: peers, lastSeens: lastSeens)
			}
		}
	}

	/// Cleans unnecessary peers from disk; must be called on AccountController.dQueue!
	private func performCleanup(allPeers: Set<Peer>, lastSeens: [PeerID: Date]) {
		let now = Date()
		let never = Date.distantPast
		let cal = Calendar.current as NSCalendar

		dataSource?.cleanup(allPeers: allPeers.map { $0.id }, { cleanupPeerIDs in
			let removePeerIDs = cleanupPeerIDs.filter { peerID in
				let lastSeenAgoCalc = cal.components(NSCalendar.Unit.hour, from: lastSeens[peerID] ?? never, to: now, options: []).hour
				let lastSeenAgo = lastSeenAgoCalc ?? PeeringController.MaxRememberedHours + 1
				return lastSeenAgo > PeeringController.MaxRememberedHours
			}

			self.persistence.removePeers(allPeers.filter { peer in
				removePeerIDs.contains(peer.id.peerID)
			})
		})
	}

	/// Observes relevant notifications in `NotificationCenter`.
	private func observeNotifications() {
		notificationObservers.append(UserPeer.NotificationName.changed.addObserver { _ in
			self.restartAdvertising()
		})
	}

	/// Posts `connectionChangedState` notification and starts/stops the server chat module.
	private func connectionChangedState(_ newState: Bool) {
		DispatchQueue.main.async { self.viewModel.peering = newState }
		Notifications.connectionChangedState.postAsNotification(object: self, userInfo: [NotificationInfoKey.connectionState.rawValue : NSNumber(value: newState)])
	}

	/// The current callback for distance measurement.
	private var rangeBlock: ((PeerID, PeerDistance) -> Void)? = nil

	/// The current measured PeerID.
	private var rangePeerID: PeerID?

	/// Time to re-range.
	@objc func callRange(_ timer: Timer) {
		guard let peerID = timer.userInfo as? PeerID else { return }
		self.discoveryManager.range(peerID)
	}

	/// Measure distance again.
	private func rerange(timeInterval: TimeInterval, tolerance: TimeInterval, distance: PeerDistance) {
		guard let rangeBlock = self.rangeBlock, let peerID = self.rangePeerID else { return }

		let timer: Timer
		if #available(iOS 10.0, *) {
			timer = Timer(timeInterval: timeInterval, repeats: false) { _ in
				self.discoveryManager.range(peerID)
			}
		} else {
			timer = Timer(timeInterval: timeInterval, target: self, selector: #selector(callRange(_:)), userInfo: peerID, repeats: false)
		}
		timer.tolerance = tolerance

		RunLoop.main.add(timer, forMode: RunLoop.Mode.default)

		rangeBlock(peerID, distance)
	}
}
