//
//  ServerChatError.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.03.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation

/// An `error` created by the server chat module.
public enum ServerChatError: Error {
	/// Thrown when server chat is used when `AccountController.shared.accountExists` is false.
	case identityMissing

	/// Parsing a server response failed; passes a localized error message.
	case parsing(String)

	/// Passes on an error produces by the SDK.
	case sdk(Error)

	/// Passes on a fatal error.
	case fatal(Error)
}
