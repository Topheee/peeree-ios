//
//  AuthenticationMiddleware.swift
//  Peeree
//
//  Created by Christopher Kobusch on 02.02.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

// Platform dependencies
import Foundation

// Internal dependencies
import PeereeCore

// External dependencies
import OpenAPIRuntime
import HTTPTypes

/// A client middleware that injects the auth token into the `Authorization` header field.
struct AuthenticationMiddleware: Sendable {
	/// Authentication token provider.
	let authenticator: PeereeCore.Authenticator

	/// Creates a new middleware.
	init(authenticator: PeereeCore.Authenticator) {
		self.authenticator = authenticator
	}
}

extension AuthenticationMiddleware: ClientMiddleware {
	func intercept(
		_ request: HTTPTypes.HTTPRequest,
		body: OpenAPIRuntime.HTTPBody?, baseURL: URL, operationID: String,
		next: @Sendable (HTTPTypes.HTTPRequest, OpenAPIRuntime.HTTPBody?, URL)
			async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?)
	) async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?) {

		// Inject the token into the header.
		var requestCopy = request
		requestCopy.headerFields[.authorization] =
			try await authenticator.accessToken()

		// Inject the token into the request and call the next middleware.
		return try await next(requestCopy, body, baseURL)
	}
}

