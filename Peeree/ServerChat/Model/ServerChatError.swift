//
//  ServerChatError.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.03.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation

/// Causes for `ServerChatError.cannotChat` error.
public enum ServerChatCannotChatReason {
	/// This user has no chat profile.
	case noProfile

	/// This user does not support E2EE.
	case noEncryption

	/// This user has not yet joined our direct chat room.
	case notJoined

	/// This user has unmatched us.
	case unmatched
}

/// An `error` created by the server chat module.
public enum ServerChatError: Error {
	/// Thrown when server chat is used when the `AccountController` singleton does not exist.
	case identityMissing

	/// Thrown when we are not able to chat with a peer for `reason`.
	case cannotChat(PeerID, ServerChatCannotChatReason)

	/// Parsing a server response failed; passes a localized error message.
	case parsing(String)

	/// Passes on an error produces by the SDK.
	case sdk(Error)

	/// Passes on a fatal error.
	case fatal(Error)
}
