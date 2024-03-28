//
//  ServerChatModel.swift
//  Peeree
//
//  Created by Christopher Kobusch on 29.03.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import MatrixSDK
import PeereeCore

// MARK: Functions

/// The Matrix domain.
let serverChatDomain = "chat.peeree.de"

let homeServerURL = URL(string: "https://\(serverChatDomain):8448/")!

/// The app group.
let messagingAppGroup = "group.86J6LQ96WM.de.peeree.messaging"

extension PeerID {
	/// Use our string representation as a server chat username.
	public var serverChatUserName: String {
		return uuidString.lowercased()
	}

	/// Transform `peerID` into a ('fully qualified') server chat user ID.
	public var serverChatUserId: String {
		return "@\(serverChatUserName):\(serverChatDomain)"
	}
}

/// Extract the `PeerID` from a ('fully qualified') server chat user ID `userId`.
func peerIDFrom(serverChatUserId userId: String) -> PeerID? {
	guard userId.count > 0,
		  let atIndex = userId.firstIndex(of: "@"),
		  let colonIndex = userId.firstIndex(of: ":") else { return nil }

	return PeerID(uuidString: String(userId[userId.index(after: atIndex)..<colonIndex]))
}

// MARK: Types

extension ChatMessage {
	/// Extracts the ID, message and timestamp from `event`.
	init(messageEvent event: MXEvent, ourUserId: String) throws {
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
		self.sent = event.sender == ourUserId
	}
}
