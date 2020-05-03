//
//  PeeringController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 04.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation

public protocol RemotePeering {
	var availablePeers: [PeerID] { get }
	var isBluetoothOn: Bool { get }
}

/// The PeeringController singleton is the app's interface to the bluetooth network as well as to information about pinned peers.
public final class PeeringController : LocalPeerManagerDelegate, RemotePeerManagerDelegate {
	public static let shared = PeeringController()
	
	public enum NotificationInfoKey: String {
		case peerID, again
	}
	
	public enum Notifications: String {
		case connectionChangedState
		case peerAppeared, peerDisappeared
		
		func post(_ peerID: PeerID?, again: Bool? = nil) {
			var userInfo: [AnyHashable: Any]? = nil
			if let id = peerID {
				if let a = again {
					userInfo = [NotificationInfoKey.peerID.rawValue : id, NotificationInfoKey.again.rawValue : a]
				} else {
					userInfo = [NotificationInfoKey.peerID.rawValue : id]
				}
			}
			postAsNotification(object: PeeringController.shared, userInfo: userInfo)
		}
	}
	
	let _local = LocalPeerManager()
	let _remote = RemotePeerManager()
	
	private var peerManagers = SynchronizedDictionary<PeerID, PeerManager>(queueLabel: "com.peeree.peerManagers")
	
	public let remote: RemotePeering
	
	public var peering: Bool {
		get {
			return _local.isAdvertising
		}
		set {
			if newValue {
				guard AccountController.shared.accountExists else { return }
				
				_local.startAdvertising()
				_remote.scan()
			} else {
				_local.stopAdvertising()
				_remote.stopScan()
			}
		}
	}
	
	public func manager(for peerID: PeerID) -> PeerManager {
		guard peerID != UserPeerManager.instance.peerID else { return UserPeerManager.instance }
		return peerManagers.accessSync { (managers) in
			guard let _manager = managers[peerID] else {
				let manager = PeerManager(peerID: peerID)
				managers[peerID] = manager
				return manager
			}
			return _manager
		}
	}
	
	// MARK: LocalPeerManagerDelegate
	
	func advertisingStarted() {
		connectionChangedState()
	}
	
	func advertisingStopped() {
		_remote.stopScan() // stop scanning when we where de-authorized
		connectionChangedState()
		peerManagers.removeAll()
	}
	
	func localPeerDelegate(for peerID: PeerID) -> LocalPeerDelegate {
		return DispatchQueue.main.sync { self.manager(for: peerID) }
	}
	
	// MARK: RemotePeerManagerDelegate
	
	func peerAppeared(_ peerID: PeerID, again: Bool) -> RemotePeerDelegate {
		Notifications.peerAppeared.post(peerID, again: again)
		// always send pin match indication on new connect to be absolutely sure that the other really got that
		let manager = self.manager(for: peerID)
		manager.indicatePinMatch()
		return manager
	}
	
	func peerDisappeared(_ peerID: PeerID, cbPeerID: UUID) {
		_local.disconnect(cbPeerID)
		Notifications.peerDisappeared.post(peerID)
	}
	
	// MARK: Private Methods
	
	private init() {
		remote = _remote
		_remote.delegate = self
		_local.delegate = self
	}
	
	private func connectionChangedState() {
		Notifications.connectionChangedState.postAsNotification(object: nil)
	}
}
