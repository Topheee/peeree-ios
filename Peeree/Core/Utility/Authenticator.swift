//
//  Authenticator.swift
//  Peeree
//
//  Created by Christopher Kobusch on 02.02.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

/// Critical data of an IdP access token.
public struct AccessTokenData: Sendable {
	/// The IdP access token itself.
	public let accessToken: String

	/// When the IdP access token expires.
	public let expiresAt: Date

	public init(accessToken: String, expiresAt: Date) {
		self.accessToken = accessToken
		self.expiresAt = expiresAt
	}
}

/// Provides access to a Peeree API.
public protocol Authenticator: Sendable {

	/// Provides for an access token to the API.
	func accessToken() async throws -> AccessTokenData
}
