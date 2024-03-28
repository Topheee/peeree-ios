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

	/// Load old, offline available messages.
	func fetchMessagesFromStore(peerID: PeerID, count: Int)

	/// Load old messages.
	func paginateUp(peerID: PeerID, count: Int, _ completion: @escaping (Error?) -> ())

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
	func decryptionError(_ error: Error, peerID: PeerID, recreateRoom: @escaping @Sendable () -> Void)

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
