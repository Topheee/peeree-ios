//
//  ServerChatViewModelDelegate.swift
//  PeereeServerChat
//
//  Created by Christopher Kobusch on 16.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import PeereeCore

/// Interface between the server chat module and the UI.
@MainActor
public protocol ServerChatViewModelDelegate: Sendable, PersonAspectState
where Aspect: ServerChatPersonAspect, RequiredData == Void {

	/// Sent or received a new message.
	func new(message: ChatMessage, inChatWithConversationPartner peerID: PeerID)

	/// Received and sent many new messages.
	func catchUp(messages: [ChatMessage], sorted: Bool, unreadCount: Int, with peerID: PeerID)
}
