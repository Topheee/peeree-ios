//
//  ServerChat.swift
//  Peeree
//
//  Created by Christopher Kobusch on 18.04.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import MatrixSDK
import PeereeCore

/// Communications through a matrix session (`MXSession`); only access directly through `ServerChatFactory.chat()` to be on the right dispatch queue!
public protocol ServerChat {
	/// Checks whether `peerID` can receive or messages.
	func canChat(with peerID: PeerID, _ completion: @escaping (ServerChatError?) -> Void)

	/// Send a message to recipient identified by `peerID`.
	func send(message: String, to peerID: PeerID, _ completion: @escaping (Result<String?, ServerChatError>) -> Void)

	/// Load old messages.
	func paginateUp(peerID: PeerID, count: Int)

	/// Configure remote push notifications.
	func configurePusher(deviceToken: Data)

	/// Sends read receipts for all messages with `peerID`.
	func markAllMessagesRead(of peerID: PeerID)

	/// Sets the last read date of one specific chat.
	func set(lastRead date: Date, of peerID: PeerID)

	/// Create chat room with `peerID`, after we have a pin match.
	func initiateChat(with peerID: PeerID)

	/// Leave chat room with `peerID`, after it was unmatched.
	func leaveChat(with peerID: PeerID)
}

/// Information provider for the server chat.
public protocol ServerChatDataSource {
	/// Informed party.
	var delegate: ServerChatDelegate? { get }

	/// Informed party about chats.
	var conversationDelegate: ServerChatConversationDelegate? { get }

	/// Queries for the PeerID that identifies ourselves and will be used as the username for the chat server.
	func ourPeerID(_ result: @escaping (PeerID?) -> ())

	/// Queries pin state of peers.
	func hasPinMatch(with peerIDs: [PeerID], forceCheck: Bool, _ result: @escaping (PeerID, Bool) -> ())
}

/// Server chat informed party.
public protocol ServerChatDelegate: AnyObject {
	/// Configuring the Pusher on the server chat server failed.
	func configurePusherFailed(_ error: Error)

	/// Joining a server chat room failed.
	func cannotJoinRoom(_ error: Error)

	/// Decrypting an encrypted server chat event failed; call `recreateRoom` to re-create the room (losing all messages).
	func decryptionError(_ error: Error, peerID: PeerID, recreateRoom: @escaping () -> Void)

	/// The certificate of the server is invalid.
	func serverChatCertificateIsInvalid()

	/// The server chat session disconnected.
	///
	/// - Parameter error: Set if the server chat session became invalid.
	func serverChatClosed(error: Error?)

	/// An unexpected error occurred, mostly network-related; use for logging.
	func serverChatInternalErrorOccured(_ error: Error)

	/// An unexpected error occurred when loading auxilarily chat data.
	func decodingPersistedChatDataFailed(with error: Error)

	/// An unexpected error occurred when storing auxilarily chat data.
	func encodingPersistedChatDataFailed(with error: Error)
}

/// Interface for interactions with a peer coming from the server chat module.
public protocol ServerChatConversationDelegate: AnyObject {
	/// Received a new message.
	func received(message: String, at: Date, from peerID: PeerID)

	/// Sent a new message.
	func didSend(message: String, at: Date, to peerID: PeerID)

	/// Received and sent many new messages.
	func catchUp(messages: [Transcript], unreadCount: Int, with peerID: PeerID)
}

/// Representation of a chat message.
public struct Transcript {
	/// From where the message was sent.
	public enum Direction {
		case send, receive
	}

	/// From where the message was sent.
	public let direction: Direction

	/// Content of the message.
	public let message: String

	/// When the message was sent.
	public let timestamp: Date
}
