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
	func loadPicture(callback: @escaping (Progress?) -> ())
	func loadBio(callback: @escaping (Progress?) -> ())
	func verify()
	func range(_ block: @escaping (PeerID, PeerDistance) -> Void)
	func stopRanging()
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
