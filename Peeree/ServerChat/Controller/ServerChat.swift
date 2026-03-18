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

/// The actor of the Server Chat module.
@globalActor public actor ChatActor {
	// https://forums.swift.org/t/actor-assumeisolated-erroneously-crashes-when-using-a-dispatch-queue-as-the-underlying-executor/72434
	final class DispatchQueueExecutor: SerialExecutor {
		private let queue: DispatchQueue

		init(queue: DispatchQueue) {
			self.queue = queue
		}

		func enqueue(_ job: UnownedJob) {
			self.queue.async {
				job.runSynchronously(on: self.asUnownedSerialExecutor())
			}
		}

		func asUnownedSerialExecutor() -> UnownedSerialExecutor {
			UnownedSerialExecutor(ordinary: self)
		}
	}

	public static let shared = ChatActor()

	public static var sharedUnownedExecutor: UnownedSerialExecutor {
		return UnownedSerialExecutor(
			ordinary: DispatchQueueExecutor(queue: self.dQueue))
	}

	/// DispatchQueue for all actions on a `ServerChatFactory`.
	static let dQueue: DispatchQueue = DispatchQueue(label: "de.peeree.ServerChat", qos: .default)

//	public nonisolated var unownedExecutor: UnownedSerialExecutor {
//		return Self.sharedUnownedExecutor
//	}
}

/// Communications through a matrix session (`MXSession`); only access directly through `ServerChatFactory.chat()` to be on the right dispatch queue!
public protocol ServerChat: Sendable {

	/// Send a message to recipient identified by `peerID`.
	/// - Throws: `ServerChatError`.
	func send(message: String, to peerID: PeerID) async throws

	/// Load old, offline available messages.
	func fetchMessagesFromStore(peerID: PeerID, count: Int) async

	/// Load old messages.
	/// - Throws: `Error`.
	func paginateUp(peerID: PeerID, count: Int) async throws

	/// Configure remote push notifications.
	func configurePusher(deviceToken: Data) async

	/// Sends read receipts for all messages with `peerID`.
	func markAllMessagesRead(of peerID: PeerID) async

	/// Sets the last read date of one specific chat.
	func set(lastRead date: Date, of peerID: PeerID) async

	/// Create chat room with `peerID`, after we have a pin match.
	func initiateChat(with peerID: PeerID) async

	/// Leave chat room with `peerID`, after it was unmatched.
	func leaveChat(with peerID: PeerID) async

	/// Re-create a room after an unrecoverable error occurred.
	func recreateRoom(with peerID: PeerID) async throws
}

/// Information provider for the server chat.
public protocol ServerChatDataSource: Sendable {
	/// Queries pin state of peers.
	func hasPinMatch(with peerID: PeerID, forceCheck: Bool) async -> Bool?

	/// Queries for all pin-matched peers.
	func pinMatches() async -> Set<PeerID>
}

/// Server chat informed party.
public protocol ServerChatDelegate: AnyObject, Sendable {
	/// An error in the chat module occurred.
	func serverChatError(_ error: Error) async

	/// The server chat session disconnected.
	///
	/// - Parameter error: Set if the server chat session became invalid.
	func serverChatClosed(error: Error?) async
}
