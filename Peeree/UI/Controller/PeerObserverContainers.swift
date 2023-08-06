//
//  PeerObserverContainers.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.04.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import UIKit
import PeereeCore
import PeereeServerChat
import PeereeDiscovery

/// A class containing a <code>PeerObserver</code>.
protocol PeerObserverContainer: AnyObject {
	/// The `PeerID` this container shall observe; make sure to set this before you access `peerObserver`.
	var peerID: PeerID { get set }
	/// The observer doing the actual observation work.
	var peerObserver: PeerObserver { get }
}

/// Shortcuts for functions accepting a `PeerID`.
extension PeerObserverContainer {
	/// Shortcut for `PeerViewModelController.shared.viewModel(of: peerID)`.
	var model: PeerViewModel { return PeerViewModelController.shared.viewModel(of: peerID) }

	/// Shortcut for `PeerViewModelController.shared.viewModel(of: peerID)`.
	var chatModel: ServerChatViewModel { return ServerChatViewModelController.shared.viewModel(of: peerID) }

	/// Shortcut for `PeereeIdentityViewModelController.viewModel(of: peerID)`.
	var idModel: PeereeIdentityViewModel { return PeereeIdentityViewModelController.viewModel(of: peerID) }

	/// Shortcut for `PeerViewModelController.shared.modify(peerID: peerID, modifier: modifier)`.
	func modifyModel(_ modifier: (inout PeerViewModel) -> ()) {
		PeerViewModelController.shared.modify(peerID: peerID, modifier: modifier)
	}
}

/// Observer for messaging-related notifications of `PeerViewModel.NotificationName`; the `UNNotication`s are unwrapped and the functions of this protocol are called accordingly.
public protocol PeerMessagingObserver: AnyObject {
	/// Called when `PeerViewModel.NotificationName.messageQueued` is posted for the `PeerID` of this `PeerObserver`.
	func messageQueued()

	/// Called when `PeerViewModel.NotificationName.messageReceived` is posted for the `PeerID` of this `PeerObserver`.
	func messageReceived()

	/// Called when `PeerViewModel.NotificationName.messageSent` is posted for the `PeerID` of this `PeerObserver`.
	func messageSent()

	/// Called when `PeerViewModel.NotificationName.unreadMessageCountChanged` is posted for the `PeerID` of this `PeerObserver`.
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

	/// The peer this observer is observing.
	public let peerID: PeerID

	public weak var connectionStateObserver: ConnectionStateObserver?
	public weak var messagingObserver: PeerMessagingObserver? {
		didSet {
			guard (oldValue == nil && messagingObserver != nil) || (oldValue != nil && messagingObserver == nil) else { return }
			if oldValue == nil {
				messagingNotificationObservers.append(ServerChatViewModel.NotificationName.messageQueued.addPeerObserver(for: peerID) { _ in
					self.messagingObserver?.messageQueued()
				})
				messagingNotificationObservers.append(ServerChatViewModel.NotificationName.messageReceived.addPeerObserver(for: peerID) { _ in
					self.messagingObserver?.messageReceived()
				})
				messagingNotificationObservers.append(ServerChatViewModel.NotificationName.messageSent.addPeerObserver(for: peerID) { _ in
					self.messagingObserver?.messageSent()
				})
				messagingNotificationObservers.append(ServerChatViewModel.NotificationName.unreadMessageCountChanged.addPeerObserver(for: peerID) { _ in
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

	/// Removes all `messagingNotificationObservers` and removes them from the `NotificationCenter`.
	private func clearMessagingObservers() {
		for observer in messagingNotificationObservers { NotificationCenter.`default`.removeObserver(observer) }
		messagingNotificationObservers.removeAll()
	}
}
