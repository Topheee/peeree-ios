//
//  PeerViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.04.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import UIKit

/// A class containing a <code>PeerObserver</code>.
protocol PeerObserverContainer: AnyObject {
	/// make sure to set this before you access <code>peerObserver</code> or <code>peerManager</code>
	var peerID: PeerID { get set }
	var peerObserver: PeerObserver { get }
	var peerManager: PeerManager { get }
}

/// Adapter for <code>PeerObserverContainer</code>.
class PeerViewController: UIViewController, PeerObserverContainer {
	lazy var peerID: PeerID = PeerID() {
		didSet { peerObserver = PeerObserver(peerID: peerID) }
	}
	private (set) lazy var peerObserver = PeerObserver(peerID: peerID)
	var peerManager: PeerManager { return peerObserver.peerManager }
}

/// Adapter for <code>PeerObserverContainer</code>.
class PeerTableViewController: UITableViewController, PeerObserverContainer {
	lazy var peerID: PeerID = PeerID() {
		didSet { peerObserver = PeerObserver(peerID: peerID) }
	}
	private (set) lazy var peerObserver = PeerObserver(peerID: peerID)
	var peerManager: PeerManager { return peerObserver.peerManager }
}

/// Observer for messaging-related notifications of <code>PeerManager.Notifications</code>.
public protocol PeerMessagingObserver: AnyObject {
	func messageQueued()
	func messageReceived()
	func messageSent()
	func unreadMessageCountChanged()
}

/// Observer for connection state-related notifications of <code>PeeringController.Notifications</code>.
public protocol ConnectionStateObserver: AnyObject {
	func connectionChangedState(_ online: Bool)
}

/** Wrapper for peer-related in-app notifications distributed through <code>NotificationCenter.`default`</code>.
  * Automatically updates its peerManager reference when connection state changes.
  * Use this class and its members from main thread only!
**/
public class PeerObserver {
	private var connectionObserver: NSObjectProtocol?
	private var messagingNotificationObservers: [NSObjectProtocol] = []

	public let peerID: PeerID
	public lazy var peerManager: PeerManager = PeeringController.shared.manager(for: peerID)

	public weak var connectionStateObserver: ConnectionStateObserver?
	public weak var messagingObserver: PeerMessagingObserver? {
		didSet {
			guard (oldValue == nil && messagingObserver != nil) || (oldValue != nil && messagingObserver == nil) else { return }
			if oldValue == nil {
				messagingNotificationObservers.append(PeerManager.Notifications.messageQueued.addPeerObserver(for: peerID) { _ in
					self.messagingObserver?.messageQueued()
				})
				messagingNotificationObservers.append(PeerManager.Notifications.messageReceived.addPeerObserver(for: peerID) { _ in
					self.messagingObserver?.messageReceived()
				})
				messagingNotificationObservers.append(PeerManager.Notifications.messageSent.addPeerObserver(for: peerID) { _ in
					self.messagingObserver?.messageSent()
				})
				messagingNotificationObservers.append(PeerManager.Notifications.unreadMessageCountChanged.addPeerObserver(for: peerID) { _ in
					self.messagingObserver?.unreadMessageCountChanged()
				})
			} else if messagingObserver == nil {
				clearMessagingObservers()
			}
		}
	}

	public init(peerID: PeerID) {
		self.peerID = peerID

		// when we go offline, all PeerManagers are purged
		connectionObserver = PeeringController.Notifications.connectionChangedState.addObserver { [weak self] notification in
			guard let state = notification.userInfo?[PeeringController.NotificationInfoKey.connectionState.rawValue] as? NSNumber, let strongSelf = self else { return }
			if state.boolValue {
				// when we go back online, we need to update our PeerManager reference
				strongSelf.peerManager = PeeringController.shared.manager(for: peerID)
			}
			strongSelf.connectionStateObserver?.connectionChangedState(state.boolValue)
		}
	}

	deinit {
		connectionObserver.map { NotificationCenter.`default`.removeObserver($0) }
		clearMessagingObservers()
	}

	private func clearMessagingObservers() {
		for observer in messagingNotificationObservers { NotificationCenter.`default`.removeObserver(observer) }
		messagingNotificationObservers.removeAll()
	}
}
