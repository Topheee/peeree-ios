//
//  JWTToken.swift
//  PeereeIdP
//
//  Created by Christopher Kobusch on 24.12.24.
//

import JWTKit

/// Claim that contains the public key of a user, that they use to authenticate to others.
/// - Note: This public key is not necessarily the same
struct PublicKeyClaim: JWTClaim {
	var value: String
}

/// JWT definition of the `AccessToken` type from our API.
struct AccessTokenJWT: JWTPayload {
	var aud: AudienceClaim
	var exp: ExpirationClaim
	var iat: IssuedAtClaim
	var iss: IssuerClaim
	var jti: IDClaim
	var sub: SubjectClaim

	func verify(using key: some JWTAlgorithm) throws {
		try self.exp.verifyNotExpired()
	}
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
