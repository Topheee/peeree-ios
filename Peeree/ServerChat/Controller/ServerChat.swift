//
//  ServerChat.swift
//  Peeree
//
//  Created by Christopher Kobusch on 18.04.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import MatrixSDK

/// Communications through a matrix session (`MXSession`); only access directly through `ServerChatFactory.chat()` to be on the right dispatch queue!
public protocol ServerChat {
	/// Checks whether `peerID` can receive or messages.
	func canChat(with peerID: PeerID, _ completion: @escaping (ServerChatError?) -> Void)

	/// Send a message to recipient identified by `peerID`.
	func send(message: String, to peerID: PeerID, _ completion: @escaping (Result<String?, ServerChatError>) -> Void)

	/// Configure remote push notifications.
	func configurePusher(deviceToken: Data)

	/// Sends read receipts for all messages with `peerID`.
	func markAllMessagesRead(of peerID: PeerID)
}

/// Server chat informed party.
public protocol ServerChatDelegate: AnyObject {
	/// Obtain timestamps of last full reads.
	func getLastReads(_ completion: @escaping ([PeerID : Date]) -> ())

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
