//
//  TokenVerifier.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.03.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

import JWTKit

enum TokenVerifierError: Error {
	case invalidIssuerURL
}

enum TokenVerificationError: Error {
	case invalidIssuer, invalidSubject, expiredToken, invalidToken(Error)
}

extension TokenVerificationError {
	var localizedDescription: String {
		switch self {
		case .invalidIssuer:
			return "Invalid issuer"
		case .invalidSubject:
			return "Invalid subject"
		case .expiredToken:
			return "Expired token"
		case .invalidToken(_):
			return "Invalid token"
		}
	}

	var logDescription: String {
		switch self {
		case .invalidToken(let error):
			return "\(error)"
		default:
			return localizedDescription
		}
	}
}

struct TokenVerifier {

	// Signs and verifies JWTs
	private let keys = JWTKeyCollection()

	private let iss: String

	init(issuerURL: URL) throws {
		guard let host = issuerURL.host, let scheme = issuerURL.scheme else {
			throw TokenVerifierError.invalidIssuerURL
		}

		self.iss = "\(scheme)://\(host)"
	}

	func initialize(from jwksURL: URL) async throws {
		let (data, _) = try await URLSession.shared.data(from: jwksURL)

		let jwks = try JSONDecoder().decode(JWKS.self, from: data)

		try await keys.add(jwks: jwks)
	}

	/// Returns the ID of the user the token was issued to.
	func verifyIdentityToken<D>(_ token: D) async throws -> IdentityTokenJWT
	where D: DataProtocol & Sendable {
		let payload: IdentityTokenJWT
		do {
			payload = try await keys.verify(token, as: IdentityTokenJWT.self)
		} catch {
			throw TokenVerificationError.invalidToken(error)
		}

		guard payload.iss.value == self.iss else {
			throw TokenVerificationError.invalidIssuer
		}

		guard UUID(uuidString: payload.sub.value) != nil else {
			throw TokenVerificationError.invalidSubject
		}

		do {
			try payload.exp.verifyNotExpired()
		} catch {
			throw TokenVerificationError.expiredToken
		}

		return payload
	}

	/// Returns the ID of the user the token was issued to.
	func verifyAccessToken<D>(_ token: D) async throws -> AccessTokenJWT
	where D: DataProtocol & Sendable {
		let payload: AccessTokenJWT
		do {
			payload = try await keys.verify(token, as: AccessTokenJWT.self)
		} catch {
			throw TokenVerificationError.invalidToken(error)
		}

		guard payload.iss.value == self.iss else {
			throw TokenVerificationError.invalidIssuer
		}

		guard UUID(uuidString: payload.sub.value) != nil else {
			throw TokenVerificationError.invalidSubject
		}

		do {
			try payload.exp.verifyNotExpired()
		} catch {
			throw TokenVerificationError.expiredToken
		}

		return payload
	}
}


