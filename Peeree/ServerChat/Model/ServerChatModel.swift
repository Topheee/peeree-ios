//
//  ServerChatModel.swift
//  Peeree
//
//  Created by Christopher Kobusch on 29.03.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import MatrixSDK

// MARK: Functions

/// The Matrix domain.
let serverChatDomain = "chat.peeree.de"

/// The app group.
let messagingAppGroup = "group.86J6LQ96WM.de.peeree.messaging"

/// ServerChat access token key in keychain.
let ServerChatAccessTokenKeychainKey = "ServerChatAccessTokenKey"

/// Our identity in UserDefaults.
let ServerChatPeerIDKey = "ServerChatPeerIDKey"

/// Transform `peerID` into a server chat username.
func serverChatUserName(for peerID: PeerID) -> String {
	return peerID.uuidString.lowercased()
}

/// Transform `peerID` into a ('fully qualified') server chat user ID.
func serverChatUserId(for peerID: PeerID) -> String {
	return "@\(serverChatUserName(for: peerID)):\(serverChatDomain)"
}

/// Extract the `PeerID` from a ('fully qualified') server chat user ID `userId`.
func peerIDFrom(serverChatUserId userId: String) -> PeerID? {
	guard userId.count > 0,
		  let atIndex = userId.firstIndex(of: "@"),
		  let colonIndex = userId.firstIndex(of: ":") else { return nil }

	return PeerID(uuidString: String(userId[userId.index(after: atIndex)..<colonIndex]))
}

// MARK: Types

struct MessageEventData {
	let eventID: String
	let timestamp: Date
	let message: String

	/// Extracts the ID, message and timestamp from `event`.
	init(messageEvent event: MXEvent) throws {
		guard event.content["format"] == nil else {
			throw ServerChatError.parsing("Body is formatted \(String(describing: event.content["format"])), ignoring.")
		}
		let messageType = MXMessageType(identifier: event.content["msgtype"] as? String ?? "error_message_type_not_a_string")
		guard messageType == .text || messageType == .notice else {
			throw ServerChatError.parsing("Unsupported message type: \(messageType).")
		}
		guard let message = event.content["body"] as? String else {
			throw ServerChatError.parsing("Message body not a string: \(event.content["body"] ?? "<nil>").")
		}

		self.eventID = event.eventId
		self.timestamp = Date(timeIntervalSince1970: Double(event.originServerTs) / 1000.0)
		self.message = message
	}
}
