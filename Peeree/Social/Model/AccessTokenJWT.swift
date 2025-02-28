//
//  AccessTokenJWT.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.02.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

/// JWT definition of the `AccessToken` type from our API.
struct AccessTokenJWT: Codable {
	var aud: String
	var exp: Date
	var iat: Date
	var iss: String
	var jti: String
	var sub: String
}
