//
//  PeereeIdentity.swift
//  Peeree
//
//  Created by Christopher Kobusch on 17.04.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import KeychainWrapper

/// The Peeree identity of a user in the social network.
public struct PeereeIdentity: Sendable, Codable {
	// MARK: - Public and Internal

	/// Keychain property
	public static let KeyAlgorithm = AsymmetricAlgorithm.ec

	/// Keychain property
	public static let KeySize = 256 // SecKeySizes.secp256r1.rawValue as AnyObject, only available on macOS...

	/// Constructs a `PeereeIdentity` from its parts.
	public init(peerID: PeerID, publicKey: AsymmetricPublicKey) throws {
		self.peerID = peerID
		self.publicKeyData = try publicKey.externalRepresentation()
	}

	/// Constructs a `PeereeIdentity` from a `PeerID` and the binary representation of a public key.
	public init(peerID: PeerID, publicKeyData: Data) {
		self.peerID = peerID
		self.publicKeyData = publicKeyData
	}

	// MARK: Constants

	/// Unique identifier for each user.
	public let peerID: PeerID

	/// The binary representation of `publicKey`.
	public let publicKeyData: Data

	// MARK: Variables

	/// The public key of the user that authenticates them.
	public func publicKey() throws -> AsymmetricPublicKey {
		return AsymmetricKeyBacking.memory(
			AsymmetricKeyInMemory(
				data: publicKeyData,
				properties: AsymmetricKeyProperties(
					part: .publicKey, algorithm: Self.KeyAlgorithm,
					size: Self.KeySize)))
	}

	/// The binary representation of `peerID`.
	public var idData: Data { return peerID.encode() }
}

extension PeereeIdentity: Equatable {
	public static func ==(lhs: PeereeIdentity, rhs: PeereeIdentity) -> Bool {
		return lhs.peerID == rhs.peerID && lhs.publicKeyData == rhs.publicKeyData
	}
}

extension PeereeIdentity: Hashable {
	public var hashValue: Int { return peerID.hashValue ^ publicKeyData.hashValue } // TODO: no idea if XOR is a safe and good combination
	public func hash(into hasher: inout Hasher) { hasher.combine(peerID); hasher.combine(publicKeyData) }
}
