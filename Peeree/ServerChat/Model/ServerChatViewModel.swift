//
//  ServerChatViewModel.swift
//  Peeree
//
//  Created by Christopher Kobusch on 01.05.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import Foundation
import DequeModule
import PeereeCore

/// Holds current information of a peer's chat to be used in the UI. Thus, all variables and methods must be accessed from main thread!
public struct ServerChatViewModel {
	// MARK: - Public and Internal

	// MARK: Classes, Structs, Enums

	/// Keys in the `userInfo` dict of a notification.
	public enum NotificationInfoKey: String {
		case message
	}

	/// Names of notifications sent by `ServerChatViewModel`.
	public enum NotificationName: String {
		case messageQueued, messageSent, messageReceived, unreadMessageCountChanged

		func post(_ peerID: PeerID, message: String = "") {
			let userInfo: [AnyHashable : Any]
			if message != "" {
				userInfo = [PeerID.NotificationInfoKey : peerID, NotificationInfoKey.message.rawValue : message]
			} else {
				userInfo = [PeerID.NotificationInfoKey : peerID]
			}
			postAsNotification(object: nil, userInfo: userInfo)
		}
	}

	// MARK: Constants

	/// The PeerID identifying this view model.
	public let peerID: PeerID

	/// Message thread with this peer.
	public private (set) var transcripts: Deque<Transcript> = Deque()

	/// Amount of messages received, which haven't been seen yet by the user.
	public var unreadMessages: Int = 0 {
		didSet {
			guard oldValue != unreadMessages else { return }
			post(.unreadMessageCountChanged)
		}
	}

	/// A message was received from this peer.
	public mutating func received(message: String, at date: Date) {
		let transcript = Transcript(direction: .receive, message: message, timestamp: date)
		if let lastMessage = transcripts.last, lastMessage.timestamp < date {
			transcripts.append(transcript)
		} else {
			insert(messages: [transcript])
		}

		unreadMessages += 1

		post(.messageReceived, message: message)
	}

	/// A message was successfully sent to this peer.
	public mutating func didSend(message: String, at date: Date) {
		let transcript = Transcript(direction: .send, message: message, timestamp: date)
		if let lastMessage = transcripts.last, lastMessage.timestamp < date {
			transcripts.append(transcript)
		} else {
			insert(messages: [transcript])
		}

		post(.messageSent)
	}

	/// Mass-append messages. Only fires Notifications.unreadMessageCountChanged.
	public mutating func catchUp(messages: [Transcript], unreadCount: Int) {
		insert(messages: messages)
		unreadMessages = unreadCount
		post(.unreadMessageCountChanged)
	}

	/// Removes all cached transcripts.
	public mutating func clearTranscripts() {
		transcripts.removeAll(keepingCapacity: false)
	}

	// MARK: - Private

	// MARK: Methods

	/// Inserts messages into our message list in the correct order (by time).
	private mutating func insert(messages: [Transcript]) {
		guard messages.count > 0 else { return }

		// this can be optimized heavily
		transcripts.append(contentsOf: messages)
		transcripts.sort { $0.timestamp < $1.timestamp }
	}

	/// Shortcut.
	private func post(_ notification: NotificationName, message: String = "") {
		notification.post(peerID, message: message)
	}
}
