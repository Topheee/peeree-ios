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

/// Receiver of `PeeringController` events.
public protocol PeeringControllerDelegate: Sendable {
	/// Advertising the Bluetooth service stopped ungracefully.
	func advertisingStopped(with error: Error) async

	/// A serialization error occurred.
	func encodingPeersFailed(with error: Error) async

	/// A serialization error occurred.
	func decodingPeersFailed(with error: Error) async

	/// If `isAvailable`, you might call ``PeeringController/goPeering()``.
	func bluetoothNetwork(isAvailable: Bool) async

	/// Verify that this identity is actually part of the Peeree network.
	func proof(_ peerID: PeerID, publicKey: AsymmetricPublicKey,
			   identityToken: Data?) async
}

/// Names of notifications sent by `PeeringController`.
extension Notification.Name {
	/// Notification sent by `PeeringController`.
	public static
	let peerAppeared = Notification.Name("PeeringController.peerAppeared"),
		peerDisappeared = Notification.Name("PeeringController.peerDisappeared")
}

/// The PeeringController singleton is the app's interface to the bluetooth network as well as to information about stored peers.
internal final class PeeringController:
	LocalPeerManagerDelegate, DiscoveryManagerDelegate {
	// MARK: - Public and Internal

	// MARK: Variables

	private let viewModel: any DiscoveryViewModelDelegate

	/// Receives general updates and errors of the `PeeringController`.
	private let delegate: PeeringControllerDelegate

	// MARK: Methods

	/// Queries whether our Bluetooth service is 'online', meaning we are scanning and, if possible, advertising.
	public func checkPeering() -> Bool {
		return self.discoveryManager.isScanning
	}

	/// Starts scanning and, if possible, advertising.
	func goPeering(data: AdvertiseData?) throws {
		guard !self.checkPeering() else { return }

		self.discoveryManager.scan()
		if let data {
			try self.startAdvertising(data: data, restartOnly: false)
		}

		self.connectionChangedState(true)
	}

	/// Stops scanning and advertising.
	func stopPeering() {
		guard self.checkPeering() else { return }

		self.stopAdvertising()
		self.discoveryManager.stopScan()

		self.connectionChangedState(false)
	}

	/// Restart advertising if it is currently on, e.g. when the user peer data changed.
	public func restartAdvertising(data: AdvertiseData) throws {
		try startAdvertising(data: data, restartOnly: true)
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

	/// Call this after you verified the identity in `PeeringControllerDelegate.proof()`.
	public func discover(_ peerID: PeerID,
						 publicKey: KeychainWrapper.AsymmetricPublicKey) {
		self.discoveryManager.beginDiscovery(on: peerID, publicKey: publicKey)
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

	func peerAppearedAgain(_ peerID: PeerID) {
		self.updateLastSeen(of: peerID)

		// make sure the notification is sent only after the view model is updated:
		Notification.Name.peerAppeared.post(
			for: peerID, userInfo: [DiscoveryNotificationInfoKey.again: true])
	}

	func peerDisappeared(_ peerID: PeerID, cbPeerID: UUID) {
		localPeerManager?.disconnect(cbPeerID)

		self.updateLastSeen(of: peerID)

		Notification.Name.peerDisappeared.post(for: peerID)
	}

	// MARK: PeerDiscoveryOperationManagerDelegate

	func beganLoadingPortrait(_ progress: CSProgress, of peerID: PeereeCore.PeerID) {
		let fractionCompleted = progress.fractionCompleted

		let vm = self.viewModel

		// publish current fraction
		publish(to: peerID) { model in
			model.pictureProgress = fractionCompleted
		}

		// publish fraction updates
		progress.addFractionCompletedNotification { completedUnitCount, totalUnitCount, fractionCompleted in
			Task { @MainActor in
				let model = vm.persona(of: peerID)

				if completedUnitCount == totalUnitCount {
					// hide progress view
					model.pictureProgress = 0.0
				} else if fractionCompleted - model.pictureProgress > 0.02 {
					// update UI less frequently; in 2% steps
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

	private func updateLastSeen(of peerID: PeerID) {
		let now = Date()
		let p = self.persistence

		Task {
			await p.updateLastSeen(now, of: peerID)
		}

		let vm = self.viewModel
		Task { @MainActor in
			vm.updateLastSeen(of: peerID, lastSeen: now)
		}
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

	// MARK: PeerVerificationOperationManagerDelegate

	/// Verify that this identity is actually part of the Peeree network.
	func proof(_ peerID: PeerID, publicKey: AsymmetricPublicKey,
			   identityToken: Data?) {
		let d = self.delegate
		Task {
			await d.proof(peerID, publicKey: publicKey,
						  identityToken: identityToken)
		}
	}

	/// Something went wrong during the discovery.
	func peerVerificationFailed(_ error: Error, of peerID: PeerID) {
		wlog(Self.LogTag, "peer verification failed: \(error)")
	}

	/// Creates the central entry point to the Discovery module.
	internal init(
		persistence: PersistedPeersController,
		viewModel: any DiscoveryViewModelDelegate,
		delegate: PeeringControllerDelegate
	) {
		self.persistence = persistence
		self.viewModel = viewModel
		self.delegate = delegate

		discoveryManager.delegate = self
	}

	// MARK: - Private

	// MARK: Static Constants

	// Log tag.
	private static let LogTag = "PeeringController"

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

	private let persistence: PersistedPeersController

	// MARK: Methods

	/// Starts advertising our data via Bluetooth.
	public func startAdvertising(data: AdvertiseData,
								 restartOnly: Bool) throws {
		// these values MAY arrive a little late, but that is very unlikely
		self.discoveryManager.set(userIdentity: (data.peerID, data.keyPair))

		guard !restartOnly || self.localPeerManager != nil else { return }

		self.localPeerManager?.stopAdvertising()

		let l = LocalPeerManager(advertiseData: data)
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
