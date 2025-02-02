//
//  Authenticator.swift
//  Peeree
//
//  Created by Christopher Kobusch on 02.02.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

/// Provides access to a Peeree API.
public protocol Authenticator: Sendable {

	/// Provides for an access token to the API.
	func accessToken() async throws -> String
}
