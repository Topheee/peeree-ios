//
//  PeereeIdentity.swift
//  Peeree
//
//  Created by Christopher Kobusch on 17.04.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation

/// The Peeree identity of a user in the social network.
public struct PeereeIdentity: Codable {
	// MARK: - Public and Internal

	/// Keychain property
	public static let KeyType = kSecAttrKeyTypeEC
	/// Keychain property
	public static let KeySize = 256 // SecKeySizes.secp256r1.rawValue as AnyObject, only available on macOS...

	/// Constructs a `PeereeIdentity` from its parts.
	init(peerID: PeerID, publicKey: AsymmetricPublicKey) {
		self.peerID = peerID
		self.publicKey = publicKey
	}

	/// Constructs a `PeereeIdentity` from a `PeerID` and the binary representation of a public key.
	init?(peerID: PeerID, publicKeyData: Data) {
		self.peerID = peerID
		do {
			self.publicKey = try AsymmetricPublicKey(from: publicKeyData, type: Self.KeyType, size: Self.KeySize)
		} catch {
			elog("creating public key from data: \(error)")
			return nil
		}
	}

	// MARK: Constants

	public let peerID: PeerID

	/// Being a constant ensures that the public key is not overwritten after it was verified.
	public let publicKey: AsymmetricPublicKey

	// MARK: Variables

	/// The binary representation of `publicKey`.
	var publicKeyData: Data { return try! publicKey.externalRepresentation() }

	/// The binary representation of `peerID`.
	var idData: Data { return peerID.encode() }
}

extension PeereeIdentity: Equatable {
	static public func ==(lhs: PeereeIdentity, rhs: PeereeIdentity) -> Bool {
		return lhs.peerID == rhs.peerID && lhs.publicKeyData == rhs.publicKeyData
	}
}

extension PeereeIdentity: Hashable {
	public var hashValue: Int { return peerID.hashValue ^ publicKeyData.hashValue } // TODO: no idea if XOR is a safe and good combination
	public func hash(into hasher: inout Hasher) { hasher.combine(peerID); hasher.combine(publicKeyData) }
}
