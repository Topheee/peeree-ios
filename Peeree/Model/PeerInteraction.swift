//
//  PeerInteraction.swift
//  Peeree
//
//  Created by Christopher Kobusch on 22.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation

/**
 Interface for interactions with a peer from the UI thread.

 - Attention: All methods of this protocol must be called from the main thread!
 */
public protocol PeerInteraction {
	func send(message: String, completion: @escaping (Error?) -> Void)
	func loadLocalPicture()
	func loadPicture(callback: @escaping (Progress?) -> ())
	func loadBio(callback: @escaping (Progress?) -> ())
	func verify()
	func range(_ block: @escaping (PeerID, PeerDistance) -> Void)
	func stopRanging()
}

/// Interface for interactions with a peer coming from the server chat module.
protocol ServerChatManager {
	func received(message: String, at: Date)
	func didSend(message: String, at: Date)
	func catchUp(messages: [Transcript])
}

/// Representation of a chat message.
public struct Transcript {
	enum Direction {
		case send, receive
	}

	let direction: Direction
	let message: String
	let timestamp: Date
}
