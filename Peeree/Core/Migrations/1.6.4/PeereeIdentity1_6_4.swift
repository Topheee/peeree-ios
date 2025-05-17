//
//  PeereeIdentity1_6_4.swift
//  Peeree
//
//  Created by Christopher Kobusch on 10.05.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

// Platform Dependencies
import Foundation

public struct KeychainWrapper2_AsymmetricPublicKey: Sendable, Codable {
	/// Always `256`.
	public var size: Int

	/// Always `"73"`.
	public var type: String

	/// `externalRepresentation()` of a public key.
	public var key: Data

	/// Always `"0"`.
	public var keyClass: String
}

/// Model of `PeereeIdentity` as it was in v1.6.4.
public struct PeereeIdentity1_6_4: Sendable, Codable {
	// MARK: - Public and Internal

	/// Keychain property. It was always this value.
	public static let KeyType = "73"

	/// Keychain property. This was a static property as well.
	public static let KeySize = 256

	/// Keychain property. It was always this value.
	public static let KeyClass = "0"

	/// Constructs a `PeereeIdentity` from its parts.
	public init(peerID: PeerID, publicKey: KeychainWrapper2_AsymmetricPublicKey) throws {
		self.peerID = peerID
		self.publicKey = publicKey
	}

	// MARK: Constants

	/// Unique identifier for each user.
	public let peerID: PeerID

	/// The binary representation of `publicKey`.
	public let publicKey: KeychainWrapper2_AsymmetricPublicKey
}
