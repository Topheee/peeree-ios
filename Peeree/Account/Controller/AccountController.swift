//
//  AccountController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.05.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

// Platform Dependencies
import Foundation
import ImageIO
import CoreServices

// Internal Dependencies
import PeereeCore

// External Dependencies
import KeychainWrapper
import OpenAPIURLSession
import OpenAPIRuntime

/// Response data for IdP challenges.
private struct ChallengeResponse {
	/// Cryptographic signature.
	let signature: Base64EncodedData

	/// IdP operation identifier.
	let operationID: Int64
}

/// Connector to the IdP API.
public actor AccountController {

	/// Creates a new `AccountController` for the user.
	internal static func create(isTest: Bool, peerID: PeerID, keyPair: KeyPair
	) -> AccountController {
		UserDefaults.standard.set(peerID.uuidString, forKey: Self.PeerIDKey)

		return AccountController(isTest: isTest, peerID: peerID,
								 keyPair: keyPair)
	}

	/// Load account data from disk; factory method for `AccountController`.
	internal static func load(isTest: Bool, keyPair: KeyPair,
							  viewModel: AccountViewModelDelegate
	) -> AccountController? {
		guard let str = UserDefaults.standard.string(
			forKey: Self.PeerIDKey) else { return nil }
		guard let peerID = UUID(uuidString: str) else {
			flog(Self.LogTag, "our peer ID is not a UUID, deleting!")
			UserDefaults.standard.removeObject(forKey: Self.PeerIDKey)
			return nil
		}

		return AccountController(isTest: isTest, peerID: peerID,
								 keyPair: keyPair)
	}

	/// Remove the Peeree account.
	internal func deleteAccount() async throws {
		let signature = try await getSignature()

		let response = try await client.deleteAccount(headers: .init(
			operationID: signature.operationID,
			signature: signature.signature))

		let _ = try response.ok

		try keyPair.removeFromKeychain()

		UserDefaults.standard.removeObject(forKey: Self.PeerIDKey)
	}

	/// Retrieve an access token for API access.
	internal func getAccessToken() async throws -> ArraySlice<UInt8> {
		let signature = try await getSignature()

		let output = try await self.client.getAccess(headers: .init(
			operationID: signature.operationID,
			signature: signature.signature))

		switch output {
		case .badRequest(let response):
			try await handle(response, logTag: Self.LogTag)
		case .forbidden(let response):
			try await handle(response, logTag: Self.LogTag)
		case .internalServerError(let response):
			try await handle(response, logTag: Self.LogTag)
		case .undocumented(statusCode: let statusCode, let payload):
			try await handle(statusCode, payload, logTag: Self.LogTag)
		case .ok(let response):
			return try await HTTPBody.ByteChunk(
				collecting: response.body.plainText, upTo: 4096)
		}
	}

	/// Retrieve an access token for API access.
	internal func getIdentityToken(of peerID: PeerID)
	async throws -> ArraySlice<UInt8> {
		let response = try await client.getIdentity(
			path: .init(userID: peerID.uuidString))

		let body = try response.ok.body.plainText
		return try await HTTPBody.ByteChunk(collecting: body, upTo: 4096)
	}

	// MARK: Constants

	/// The crown juwels of the user and the second part of the user's identity.
	public let keyPair: KeyPair

	/// The identifier of the user on our social network.
	public let peerID: PeerID

	// MARK: - Private

	/// Creates the AccountController singleton and installs it in the rest of the app.
	private init(isTest: Bool, peerID: PeerID, keyPair: KeyPair) {
		self.peerID = peerID
		self.keyPair = keyPair
		self.isTest = isTest
	}

	// MARK: Static Constants

	// Log tag.
	private static let LogTag = "Account"

	/// Key to our identity in UserDefaults
	private static let PeerIDKey = "PeerIDKey"

	// MARK: Methods

	/// Whether the test backend should be used.
	private let isTest: Bool

	/// IdP user ID.
	private var userID: String { peerID.uuidString }

	/// Network client for IdP API access.
	private var client: Client {
		get throws {
			Client(
				serverURL: isTest ? try Servers.Server2.url() :
					try Servers.Server1.url(),
				transport: URLSessionTransport()
			)
		}
	}

	/// Retrieve challenge and calculate response.
	private func getSignature() async throws -> ChallengeResponse {
		let response = try await client
			.getChallenge(path: .init(userID: self.userID))

		switch response {
		case .badRequest(let response):
			try await handle(response, logTag: Self.LogTag)
		case .tooManyRequests(let response):
			try await handle(response, logTag: Self.LogTag)
		case .internalServerError(let response):
			try await handle(response, logTag: Self.LogTag)
		case .undocumented(statusCode: let statusCode, let payload):
			try await handle(statusCode, payload, logTag: Self.LogTag)
		case .accepted(let response):
			let challenge = try response.body.json

			let signature = try keyPair.sign(
				message: Data(challenge.nonce.data))

			return .init(
				signature: .init(signature),
				operationID: challenge.operationID)
		}
	}

	/// Wipes all data after the account was deleted.
	internal func clearLocalData() {
		UserDefaults.standard.removeObject(forKey: Self.PeerIDKey)

		do {
			try keyPair.removeFromKeychain()
		} catch let error {
			flog(Self.LogTag, "Could not delete keychain items. Creation of new identity will probably fail. Error: \(error.localizedDescription)")
		}
	}
}
