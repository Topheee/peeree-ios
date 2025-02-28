//
//  Utitlity.swift
//  Peeree
//
//  Created by Christopher Kobusch on 23.02.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

// Internal Dependencies
import PeereeCore

// External Dependencies
import OpenAPIRuntime

// TODO: localize this file

internal func logOpenAPIError(tag: String, message: String,
							  _ body: HTTPBody) async {
	do {
		let serverMessage = try await String(collecting: body, upTo: 4096)
		elog(tag, "\(message): \(serverMessage)")
	} catch {
		elog(tag, "\(message): FAILED TO PARSE BODY: \(error)")
	}
}

/// Handle API error.
internal func handle(
	_ response: Components.Responses.ClientSideErrorResponse,
	logTag: String
) async throws -> Never {
	await logOpenAPIError(tag: logTag, message: "Account client side error",
						  try response.body.plainText)
	throw createApplicationError(
		localizedDescription: "IdP programming error.")
}

/// Handle API error.
internal func handle(
	_ response: Components.Responses.InvalidSignatureResponse,
	logTag: String
) async throws -> Never {
	await logOpenAPIError(tag: logTag,
						  message: "Account invalid signature error",
						  try response.body.plainText)
	throw createApplicationError(
		localizedDescription: "Severe IdP programming error.")
}

/// Handle API error.
internal func handle(_ response: Components.Responses.RateLimitResponse,
					logTag: String
) async throws -> Never {
	await logOpenAPIError(tag: logTag, message: "Rate limit error",
					try response.body.plainText)
	throw createApplicationError(
		localizedDescription: "Too many requests to IdP.")
}

/// Handle API error.
internal func handle(
	_ response: Components.Responses.ServerSideErrorResponse,
	logTag: String
) async throws -> Never {
	await logOpenAPIError(tag: logTag, message: "Server side error",
						  try response.body.plainText)
	throw createApplicationError(localizedDescription: "IdP server error.")
}

/// Handle API error.
internal func handle(
	_ statusCode: Int, _ payload: OpenAPIRuntime.UndocumentedPayload,
	logTag: String
) async throws -> Never {
	if let body = payload.body {
		await logOpenAPIError(tag: logTag, message: "Undocumented IdP error",
							  body)
	} else {
		elog(logTag, "Undocumented IdP error \(statusCode)")
	}

	throw createApplicationError(
		localizedDescription: "Unknown IdP error \(statusCode).")
}
