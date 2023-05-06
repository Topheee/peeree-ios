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
public struct PeereeIdentity: Codable {
	// MARK: - Public and Internal

	/// Keychain property
	public static let KeyType = kSecAttrKeyTypeEC

	/// Keychain property
	public static let KeyAlgorithm = AsymmetricAlgorithm.ec

	/// Keychain property
	public static let KeySize = 256 // SecKeySizes.secp256r1.rawValue as AnyObject, only available on macOS...

	/// Constructs a `PeereeIdentity` from its parts.
	public init(peerID: PeerID, publicKey: AsymmetricPublicKey) {
		self.peerID = peerID
		self.publicKey = publicKey
	}

	/// Constructs a `PeereeIdentity` from a `PeerID` and the binary representation of a public key.
	public init(peerID: PeerID, publicKeyData: Data) throws {
		self.peerID = peerID
		self.publicKey = try AsymmetricPublicKey(from: publicKeyData, algorithm: Self.KeyAlgorithm, size: Self.KeySize)
	}

	// MARK: Constants

	public let peerID: PeerID

	/// Being a constant ensures that the public key is not overwritten after it was verified.
	public let publicKey: AsymmetricPublicKey

	// MARK: Variables

	/// The binary representation of `publicKey`.
	public var publicKeyData: Data { return try! publicKey.externalRepresentation() }

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
