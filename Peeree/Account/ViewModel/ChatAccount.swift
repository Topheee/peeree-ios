//
//  ChatAccount.swift
//  Peeree
//
//  Created by Christopher Kobusch on 23.02.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

public struct ChatAccount: Sendable {
	public let userID: String
	public let accessToken: String
	public let homeServer: String
	public let deviceID: String
	public let initialPassword: String
}

