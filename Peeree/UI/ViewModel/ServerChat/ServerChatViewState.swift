//
//  ServerChatViewState.swift
//  Peeree
//
//  Created by Christopher Kobusch on 21.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeCore
import PeereeServerChat

// Global UI state.
@MainActor
final class ServerChatViewState: ObservableObject {

	// MARK: Classes, Structs, Enums

	/// Keys in the `userInfo` dict of a notification.
	public enum NotificationInfoKey: String {
		case message
	}

	/// Names of notifications sent by `ServerChatViewModel`.
	public enum NotificationName: String {
		case messageSent, messageReceived

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

	// MARK: Static Constants

	/// Global state object.
	static let shared = ServerChatViewState()

	// MARK: Variables

	/// Sorted list of pin-matched people.
	@Published var matchedPeople: [ServerChatPerson] = []

	/// The person that we currently chat with, if any.
	@Published var displayedPeerID: PeerID? = nil

	/// All chats.
	private (set) var people: [PeerID : ServerChatPerson] = [:]

	/// Controls the scroll view of the currently visible chat.
	var messagesScrollViewProxy: ScrollViewProxy? = nil

	@Published var lastMessageDisplayed = false

	// MARK: Methods

	func addPersona(of peerID: PeerID, with data: Void) -> ServerChatPerson {
		return persona(of: peerID)
	}

	// Retrieve a person.
	func persona(of peerID: PeerID) -> ServerChatPerson {
		if let p = people[peerID] {
			return p
		} else {
			let p = ServerChatPerson(peerID: peerID)
			self.people[peerID] = p
			self.matchedPeople.insert(p, at: 0)
			return p
		}
	}

	/// Removes the view model of `peerID`.
	public func removePersona(of peerID: PeerID) {
		people.removeValue(forKey: peerID)
		matchedPeople.removeAll { $0.peerID == peerID }
	}

	/// Removes all view models.
	public func clear() {
		people.removeAll()
		matchedPeople.removeAll()
	}

	// MARK: Private

	// Log tag.
	private static let LogTag = "ServerChatViewState"
}

extension ServerChatViewState: ServerChatViewModelDelegate {
	typealias RequiredData = Void

	func new(message: ChatMessage, inChatWithConversationPartner peerID: PeerID) {
		let p = persona(of: peerID)
		p.insert(messages: [message], sorted: true)

		// If peer is not shown this message is unread.
		if peerID != displayedPeerID {
			p.unreadMessages += 1
		} else if lastMessageDisplayed {
			messagesScrollViewProxy?.scrollTo(message.id, anchor: .bottom)
		}

		sortChatList()

		let n: NotificationName = message.sent ? .messageSent : .messageReceived
		n.post(peerID, message: message.message)
	}

	func catchUp(messages: [ChatMessage], sorted: Bool, unreadCount: Int, with peerID: PeerID) {
		let p = persona(of: peerID)
		p.insert(messages: messages, sorted: sorted)
		p.unreadMessages += unreadCount

		sortChatList()
	}

	private func sortChatList() {
		// Chat list should be sorted after date of last message in each chat.
		matchedPeople.sort { a, b in
			(a.lastMessage?.timestamp ?? Date.distantPast) > (b.lastMessage?.timestamp ?? Date.distantPast)
		}
	}

}
