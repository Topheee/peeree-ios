//
//  DiscoveryController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.05.26.
//  Copyright © 2026 Kobusch. All rights reserved.
//

// Internal Dependencies
import PeereeCore

// External Dependencies
import KeychainWrapper

/// Provides data for the Discovery module.
public protocol DiscoveryControllerDataSource: Sendable {
	/// Remove peers from persisted peers.
	func sortOut(peers: [Peer]) async -> [PeerID]
}

// MARK: Classes, Structs, Enums

/// Keys in the `userInfo` dict of a notification.
public enum DiscoveryNotificationInfoKey: String {
	case again
}

// The central singleton of the Discovery module.
public actor DiscoveryController {

	public init () {
	}

	/// Whether the Bluetooth stack was set up.
	public func isPeeringPrepared() -> Bool {
		return self.peeringController != nil
	}

	/// Reads data from disk and populates view model.
	public func initialize(
		dataSource: DiscoveryControllerDataSource,
		viewModel: any DiscoveryViewModelDelegate
	) async throws {
		self.dataSource = dataSource

		let (initialData, lastSeenDates) = try await self.persistence
			.loadInitialData()

		let allPeers = initialData.map(\.peer)

		let cleanupPeerIDs = await dataSource.sortOut(peers: allPeers)

		try await self.cleanupPersistedPeers(
			allPeers: Set(allPeers), cleanupPeerIDs: cleanupPeerIDs,
			lastSeenDates: lastSeenDates, viewModel: viewModel)
	}

	/// Setup Bluetooth stack.
	public func preparePeering(
		viewModel: any DiscoveryViewModelDelegate,
		pcDelegate: PeeringControllerDelegate
	) throws {
		guard self.peeringController == nil else { return }

		// first time accessing Bluetooth
		// PeeringController.isBluetoothOn is `false` in all cases here!
		// Creating a PeeringController will trigger
		// `bluetoothNetwork(isAvailable:)`, which will then automatically go
		// online
		self.peeringController = PeeringController(
			persistence: self.persistence, viewModel: viewModel,
			delegate: pcDelegate)
	}

	/// Go onto the Bluetooth network.
	public func goOnline(_ data: AdvertiseData?) throws {
		try self.peeringController?.goPeering(data: data)
	}

	/// Go off the Bluetooth network.
	public func goOffline() {
		self.peeringController?.stopPeering()
	}

	/// Read-only access to persisted peers.
	public func readPeer(_ peerID: PeerID) async -> Peer? {
		return await self.persistence.readPeer(peerID)
	}

	/// Restart advertising with fresh data.
	public func restartAdvertising(data: AdvertiseData) throws {
		try self.peeringController?.restartAdvertising(data: data)
	}

	/// Start advertising if it is not already started.
	public func startAdvertising(data: AdvertiseData) throws {
		guard let pc = self.peeringController,
			  pc.checkPeering()
		else { return }

		try pc.startAdvertising(data: data, restartOnly: false)
	}

	/// Load Bio and optionally the portrait of a peer.
	public func loadAdditionalInfo(of peerID: PeerID) {
		self.peeringController?.loadAdditionalInfo(of: peerID, loadPortrait: true)
	}

	/// Call this after you verified the identity of `peerID`.
	public func discover(
		_ peerID: PeerID,
		publicKey: KeychainWrapper.AsymmetricPublicKey
	) {
		self.peeringController?.discover(peerID, publicKey: publicKey)
	}

	/// Stop all peering activity.
	public func teardown() {
		self.peeringController?.teardown()
	}

	/// Locator of file containing the portrait of `peerID` (if available).
	public func pictureURL(of peerID: PeerID) -> URL {
		return self.persistence.pictureURL(of: peerID)
	}

	// MARK: - Private


	private static let MaxRememberedHours = 48

	private let persistence = PersistedPeersController(filename: "peers.json")

	private var peeringController: PeeringController? = nil

	private var dataSource: DiscoveryControllerDataSource? = nil

	/// Remove peers from disk which haven't been seen for `MaxRememberedHours` and are not pin matched.
	private func cleanupPersistedPeers(
		allPeers: Set<Peer>, cleanupPeerIDs: [PeerID],
		lastSeenDates: [PeerID: Date],
		viewModel: any DiscoveryViewModelDelegate
	) async throws {
		let now = Date()
		let never = Date.distantPast
		let cal = Calendar.current as NSCalendar

		let removePeerIDs = cleanupPeerIDs.filter { peerID in
			let lastSeenAgoCalc = cal.components(
				NSCalendar.Unit.hour,
				from: lastSeenDates[peerID] ?? never,
				to: now, options: []).hour

			let lastSeenAgo = lastSeenAgoCalc ?? Self.MaxRememberedHours + 1
			return lastSeenAgo > Self.MaxRememberedHours
		}

		let removePeers = allPeers.filter { peer in
			removePeerIDs.contains(peer.id.peerID)
		}

		let remainingPeers = allPeers.subtracting(removePeers)

		let p = self.persistence

		try await p.removePeers(removePeers)

		Task { @MainActor in
			for peer in remainingPeers {
				let peerID = peer.id.peerID
				_ = viewModel.addPersona(of: peerID, with: peer.info)
				viewModel.updateLastSeen(
					of: peerID,
					lastSeen: lastSeenDates[peerID] ?? Date.distantPast)
			}
		}

		Task {
			let blobs = await withTaskGroup(of: (PeerID, PeerBlobData?).self) { group in
				for peer in remainingPeers {
					group.addTask {
						(peer.id.peerID, await p.loadBlob(of: peer.id.peerID))
					}
				}

				return await group.reduce(into: [PeerID:PeerBlobData]()) { dictionary, result in
					if let blob = result.1 {
						dictionary[result.0] = blob
					}
				}
			}

			Task { @MainActor in
				blobs.forEach { (peerID, blob) in
					let p = viewModel.persona(of: peerID)

					p.biography = blob.biography
					p.set(portrait: blob.portrait, hash: blob.portraitHash)
				}
			}
		}
	}

}
