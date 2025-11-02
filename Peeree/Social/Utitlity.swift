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
	await logOpenAPIError(tag: logTag, message: "API client side error",
						  try response.body.plainText)
	throw createApplicationError(
		localizedDescription: NSLocalizedString(
			"API programming error.", comment: "Low-level API error"))
}

/// Handle API error.
internal func handle(
	_ response: Components.Responses.MissingAccessTokenResponse,
	logTag: String
) throws -> Never {
	elog(logTag, "API no token error")
	throw createApplicationError(
		localizedDescription: NSLocalizedString(
			"Severe API programming error.", comment: "Low-level API error"))
}

/// Handle API error.
internal func handle(
	_ statusCode: Int, _ payload: OpenAPIRuntime.UndocumentedPayload,
	logTag: String
) async throws -> Never {
	if let body = payload.body {
		await logOpenAPIError(tag: logTag, message: "Undocumented API error",
							  body)
	} else {
		elog(logTag, "Undocumented API error \(statusCode)")
	}

	let format = "Unknown API error %d."

	throw createApplicationError(
		localizedDescription: NSLocalizedString(
			String(format: format, statusCode), comment: "Low level IdP error"))
}
