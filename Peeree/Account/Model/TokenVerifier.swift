//
//  TokenVerifier.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.03.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

import JWTKit

/// Claim that contains the public key of a user, that they use to authenticate to others.
/// - Note: This public key is not necessarily the same
struct PublicKeyClaim: JWTClaim {
	var value: String
}


/// JWT definition of the `IdentityToken` type from our API.
struct IdentityTokenJWT: JWTPayload {
	var exp: ExpirationClaim
	var iat: IssuedAtClaim
	var iss: IssuerClaim
	var nonce: IDClaim
	var pbk: PublicKeyClaim
	var sub: SubjectClaim

	func verify(using key: some JWTAlgorithm) throws {
		try self.exp.verifyNotExpired()
	}
}

enum TokenVerifierError: Error {
	case keyNotFound, invalidPublicKey(Error)
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

	init(issuerURL: URL) {
		self.iss = issuerURL.absoluteString
	}

	func initialize(from jwksURL: URL) async throws {
		let (data, response) = try await URLSession.shared.data(from: jwksURL)

		let jwk = try JSONDecoder().decode(JWK.self, from: data)

		try await keys.add(jwks: JWKS(keys: [jwk]))
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
}


