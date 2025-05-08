//
//  AccountConfiguration.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.05.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//


/// The central configuration of the Account module.
public enum AccountModuleConfig {
	/// Production release configuration.
	case production

	/// Testing configuration.
	case testing(AccountModuleConfigTesting)
}

/// Sub-configuration for testing builds.
public struct AccountModuleConfigTesting {
	/// Takes the private key's keychain tag.
	let privateKeyTag: String

	public init(privateKeyTag: String) {
		self.privateKeyTag = privateKeyTag
	}
}
