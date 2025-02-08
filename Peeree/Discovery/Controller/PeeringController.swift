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
import CSProgress

/// An approximisation of the distance to the peer's phone.
public enum PeerDistance {
	case unknown, close, nearby, far
}

/// Main information provider for the PeereeDiscovery module.
public protocol PeeringControllerDataSource: Sendable {
	/// Return our information, s.t. we can present ourselves.
	func advertiseData() async throws -> (PeerID, KeyPair, PeerInfo, String, URL)

	/// Asks for a list of `PeerID`s which can be safely removed from disk.
	func cleanup(allPeers: [PeereeIdentity]) async -> [PeerID]
}

/// Receiver of `PeeringController` events.
public protocol PeeringControllerDelegate: Sendable {
	/// Advertising the Bluetooth service stopped ungracefully.
	func advertisingStopped(with error: Error) async

	/// A serialization error occurred.
	func encodingPeersFailed(with error: Error) async

	/// A serialization error occurred.
	func decodingPeersFailed(with error: Error) async

	/// If `isAvailable`, you might call `PeeringController.change(peering: true)`.
	func bluetoothNetwork(isAvailable: Bool) async
}

/// Names of notifications sent by `PeeringController`.
extension Notification.Name {
	/// Notification sent by `PeeringController`.
	public static
	let peerAppeared = Notification.Name("PeeringController.peerAppeared"),
		peerDisappeared = Notification.Name("PeeringController.peerDisappeared")
}

/// The PeeringController singleton is the app's interface to the bluetooth network as well as to information about stored peers.
public final class PeeringController:
	LocalPeerManagerDelegate, DiscoveryManagerDelegate {
	// MARK: - Public and Internal

	// MARK: Classes, Structs, Enums

	/// Keys in the `userInfo` dict of a notification.
	public enum NotificationInfoKey: String {
		case again
	}

	// MARK: Variables

	private let viewModel: any DiscoveryViewModelDelegate

	/// Provider of information.
	private let dataSource: PeeringControllerDataSource

	/// Receives general updates and errors of the `PeeringController`.
	private let delegate: PeeringControllerDelegate

	// MARK: Methods

	/// Queries whether our Bluetooth service is 'online', meaning we are scanning and, if possible, advertising.
	public func checkPeering() async -> Bool {
		return self.discoveryManager.isScanning
	}

	/// Controls whether our Bluetooth service is 'online', meaning we are scanning and, if possible, advertising.
	public func change(peering newValue: Bool) async throws {
		guard newValue != self.discoveryManager.isScanning else { return }

		if newValue {
			self.discoveryManager.scan()
			try await self.startAdvertising(restartOnly: false)
		} else {
			self.stopAdvertising()
			self.discoveryManager.stopScan()
		}

		self.connectionChangedState(newValue)
	}

	/// Restart advertising if it is currently on, e.g. when the user peer data changed.
	public func restartAdvertising() async throws {
		try await startAdvertising(restartOnly: true)
	}

	/// Stop all peering activity.
	public func teardown() {
		discoveryManager.set(userIdentity: nil)

		let p = self.persistence
		let vm = self.viewModel
		Task {
			// delete all cached pictures and finally the persisted PeerInfo records themselves
			await p.clear()
			await vm.clear()
		}
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

	/// Read-only access to persisted peers.
	public func readPeer(_ peerID: PeerID) async -> Peer? {
		return await persistence.readPeer(peerID)
	}

	// MARK: LocalPeerManagerDelegate

	func advertisingStarted() {}

	func advertisingStopped(with error: Error?) {
		_ = error.map { e in
			let d = self.delegate
			Task { await d.advertisingStopped(with: e) } }
	}

	func authenticationFromPeerFailed(_ peerID: PeerID, with error: Error) {
		// ignored for now, since we do not rely on authentication via Bluetooth (was only necessary for messaging, which is not used anymore)
	}

	func characteristicSigningFailed(with error: Error) {
		stopAdvertising()
		let d = self.delegate
		Task { await d.advertisingStopped(with: error) }
	}

	func receivedPinMatchIndication(from peerID: PeerID) {
		// ignored
	}

	// MARK: DiscoveryManagerDelegate

	func beganLoadingPortrait(_ progress: CSProgress, of peerID: PeereeCore.PeerID) {
		let fractionCompleted = progress.fractionCompleted

		let vm = self.viewModel

		// publish current fraction
		publish(to: peerID) { model in
			model.pictureProgress = fractionCompleted
		}

		// publish fraction updates
		progress.addFractionCompletedNotification { _, _, fractionCompleted in
			Task { @MainActor in
				let model = vm.persona(of: peerID)
				// update UI less frequently; in 2% steps
				if fractionCompleted - model.pictureProgress > 0.02 {
					model.pictureProgress = fractionCompleted
				}
			}
		}
	}

	func peerDiscoveryFinished(peerLastChangedDate: Date, of peerID: PeereeCore.PeerID) {
		self.discoveryManager.discoveryCompleted(of: peerID, lastChanged: peerLastChangedDate)
		self.discoveryManager.closeConnection(with: peerID)
	}

	func peerDiscoveryFailed(_ error: Error) {
		wlog(Self.LogTag, "peer discovery failed: \(error)")
	}

	func discoveryManager(isReady: Bool) {
		let vm = self.viewModel
		let d = self.delegate
		Task { @MainActor in
			vm.isBluetoothOn = isReady
			Task {
				await d.bluetoothNetwork(isAvailable: isReady)
			}
		}
	}

	func scanningStopped() {
		stopAdvertising()
		connectionChangedState(false)
	}

	private func updateLastSeen(of peerID: PeerID) {
		let now = Date()
		self.lastSeenDates[peerID] = now
		archiveObjectInUserDefs(self.lastSeenDates as NSDictionary, forKey: Self.LastSeenKey)

		let vm = self.viewModel
		Task { @MainActor in
			vm.updateLastSeen(of: peerID, lastSeen: now)
		}
	}

	func peerAppearedAgain(_ peerID: PeerID) {
		self.updateLastSeen(of: peerID)

		// make sure the notification is sent only after the view model is updated:
		Notification.Name.peerAppeared.post(for: peerID, userInfo: [Self.NotificationInfoKey.again: true])
	}

	func peerDisappeared(_ peerID: PeerID, cbPeerID: UUID) {
		localPeerManager?.disconnect(cbPeerID)

		self.updateLastSeen(of: peerID)

		Notification.Name.peerDisappeared.post(for: peerID)
	}

	func loaded(info: PeerInfo, of identity: PeereeIdentity) {
		let peer = Peer(id: identity, info: info)

		let p = self.persistence
		let d = self.delegate
		Task {
			do {
				try await p.addPeers([peer])
			} catch {
				await d.encodingPeersFailed(with: error)
			}
		}

		let vm = self.viewModel

		Task { @MainActor in
			Self.updateViewModels(of: peer, lastSeen: Date(), on: vm)

			Notification.Name.peerAppeared.post(for: peer.id.peerID)
		}
	}

	func loaded(picture: CGImage, of peerID: PeereeCore.PeerID, hash: Data) {
		let p = self.persistence
		let d = self.delegate

		Task {
			do {
				try await p.writeBlob(of: peerID) { blob in
					blob.portrait = picture
				}
			} catch {
				await d.encodingPeersFailed(with: error)
			}
		}

		obtained(picture, hash: hash, of: peerID)
	}

	func loaded(biography: String, of peerID: PeereeCore.PeerID) {
		let p = self.persistence
		let d = self.delegate

		Task {
			do {
				try await p.writeBlob(of: peerID) { blob in
					blob.biography = biography
				}
			} catch {
				await d.encodingPeersFailed(with: error)
			}
		}

		publish(to: peerID) { model in
			model.biography = biography
		}
	}

	func didRange(_ peerID: PeerID, rssi: NSNumber?, error: Error?) {
		guard error == nil else {
			elog(Self.LogTag, "Error updating range: \(error!.localizedDescription)")
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
		// ignored
	}

	/// Creates the central entry point to the Discovery module.
	public init(viewModel: any DiscoveryViewModelDelegate, dataSource: PeeringControllerDataSource, delegate: PeeringControllerDelegate) {
		self.viewModel = viewModel
		self.dataSource = dataSource
		self.delegate = delegate

		discoveryManager.delegate = self
	}

	/// Load data from disk and publish it to the view model.
	public func initialize() async throws {
		let nsLastSeenDates: NSDictionary? = unarchiveObjectFromUserDefs(
			PeeringController.LastSeenKey,
			containing: [NSUUID.self, NSDate.self])

		let lsDates = nsLastSeenDates as? [PeerID : Date] ?? [PeerID : Date]()
		self.lastSeenDates = lsDates

		let peers = try await persistence.loadInitialData()

		await self.cleanupPersistedPeers(allPeers: Set(peers.map { $0.0 }),
										 lastSeens: lsDates)

		let vm = self.viewModel

		Task { @MainActor in

			for peer in peers {
				Self.updateViewModels(
					of: peer.0,
					lastSeen: lsDates[peer.0.id.peerID] ?? Date.distantPast,
					on: vm)

				vm.persona(of: peer.0.id.peerID).biography = peer.1.biography
			}
		}
	}

	// MARK: - Private

	// MARK: Static Constants

	// Log tag.
	private static let LogTag = "PeeringController"

	private static let LastSeenKey = "RecentPeersController.LastSeenKey"
	private static let MaxRememberedHours = 48

	// MARK: Static Methods

	/// Populates the current peer-related data to the view models; must be called on the main thread!
	@MainActor
	private static func updateViewModels(of peer: Peer, lastSeen: Date, on viewModel: any DiscoveryViewModelDelegate) {
		let peerID = peer.id.peerID

		_ = viewModel.addPersona(of: peerID, with: peer.info)
		viewModel.updateLastSeen(of: peerID, lastSeen: lastSeen)
	}

	// MARK: Constants

	/// Responsible for advertising the user's data; access only through `dataSource` callbacks.
	private var localPeerManager: LocalPeerManager? = nil
	private let discoveryManager = DiscoveryManager()

	private let persistence = PersistedPeersController(filename: "peers.json")

	// MARK: Variables

	/// when was a specific PeerID last encountered via Bluetooth.
	private var lastSeenDates: [PeerID : Date] = [:]

	// MARK: Methods

	/// Starts advertising our data via Bluetooth.
	public func startAdvertising(restartOnly: Bool) async throws {
		let (peerID, keyPair, info, biography, pictureResourceURL) = try await dataSource.advertiseData()

		// these values MAY arrive a little late, but that is very unlikely
		self.discoveryManager.set(userIdentity: (peerID, keyPair))

		guard !restartOnly || self.localPeerManager != nil else { return }

		self.localPeerManager?.stopAdvertising()

		let l = LocalPeerManager(peer: Peer(id: try PeereeIdentity(peerID: peerID, publicKey: keyPair.publicKey), info: info),
								 biography: biography, keyPair: keyPair, pictureResourceURL: pictureResourceURL)
		self.localPeerManager = l
		l.delegate = self
		l.startAdvertising()
	}

	/// Stops advertising our data via Bluetooth.
	private func stopAdvertising() {
		self.localPeerManager?.stopAdvertising()
		self.localPeerManager = nil
	}

	/// publish changes to the model on the main thread
	private func publish(to peerID: PeerID, _ query: @MainActor @escaping (any DiscoveryPersonAspect) -> ()) {
		let vm = self.viewModel
		Task { @MainActor in
			query(vm.persona(of: peerID))
		}
	}

	/// Performs additional logic when a picture was received, e.g. objectionable content checks.
	private func obtained(_ picture: CGImage, hash: Data, of peerID: PeerID) {
		self.publish(to: peerID) { model in
			model.set(portrait: picture, hash: hash)
		}
	}

	/// Remove peers from disk which haven't been seen for `MaxRememberedHours` and are not pin matched.
	private func cleanupPersistedPeers(allPeers: Set<Peer>, lastSeens: [PeerID : Date]) async {
		let now = Date()
		let never = Date.distantPast
		let cal = Calendar.current as NSCalendar

		let cleanupPeerIDs = await dataSource.cleanup(allPeers: allPeers.map { $0.id })

		let removePeerIDs = cleanupPeerIDs.filter { peerID in
			let lastSeenAgoCalc = cal.components(NSCalendar.Unit.hour, from: lastSeens[peerID] ?? never, to: now, options: []).hour
			let lastSeenAgo = lastSeenAgoCalc ?? PeeringController.MaxRememberedHours + 1
			return lastSeenAgo > PeeringController.MaxRememberedHours
		}

		do {
			try await self.persistence.removePeers(allPeers.filter { peer in
				removePeerIDs.contains(peer.id.peerID)
			})
		} catch {
			await self.delegate.encodingPeersFailed(with: error)
		}
	}

	/// Changes the state in the UI.
	private func connectionChangedState(_ newState: Bool) {
		let vm = self.viewModel
		Task { @MainActor in
			//UISelectionFeedbackGenerator().selectionChanged()
			vm.peering = newState
		}
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
//		if #available(iOS 10.0, *) {
//			timer = Timer(timeInterval: timeInterval, repeats: false) { _ in
//				self.discoveryManager.range(peerID)
//			}
//		} else {
			timer = Timer(timeInterval: timeInterval, target: self, selector: #selector(callRange(_:)), userInfo: peerID, repeats: false)
//		}
		timer.tolerance = tolerance

		RunLoop.main.add(timer, forMode: RunLoop.Mode.default)

		rangeBlock(peerID, distance)
	}
}
