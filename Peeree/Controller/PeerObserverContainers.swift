//
//  PeerObserverContainers.swift
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
}

extension PeerObserverContainer {
	var model: PeerViewModel { return PeerViewModelController.viewModel(of: peerID) }

	func interactWithPeer(completion: @escaping (PeerInteraction) -> ()) {
		PeeringController.shared.interact(with: peerID, completion: completion)
	}

	func modifyModel(_ modifier: (inout PeerViewModel) -> ()) {
		PeerViewModelController.modify(peerID: peerID, modifier: modifier)
	}
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

	public weak var connectionStateObserver: ConnectionStateObserver?
	public weak var messagingObserver: PeerMessagingObserver? {
		didSet {
			guard (oldValue == nil && messagingObserver != nil) || (oldValue != nil && messagingObserver == nil) else { return }
			if oldValue == nil {
				messagingNotificationObservers.append(PeerViewModel.NotificationName.messageQueued.addPeerObserver(for: peerID) { _ in
					self.messagingObserver?.messageQueued()
				})
				messagingNotificationObservers.append(PeerViewModel.NotificationName.messageReceived.addPeerObserver(for: peerID) { _ in
					self.messagingObserver?.messageReceived()
				})
				messagingNotificationObservers.append(PeerViewModel.NotificationName.messageSent.addPeerObserver(for: peerID) { _ in
					self.messagingObserver?.messageSent()
				})
				messagingNotificationObservers.append(PeerViewModel.NotificationName.unreadMessageCountChanged.addPeerObserver(for: peerID) { _ in
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
			guard let state = notification.userInfo?[PeeringController.NotificationInfoKey.connectionState.rawValue] as? NSNumber else { return }
			self?.connectionStateObserver?.connectionChangedState(state.boolValue)
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
