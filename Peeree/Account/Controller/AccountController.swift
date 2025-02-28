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

/// Connector to the IdP API.
public actor AccountController {

	/// Creates a new `AccountController` for the user.
	internal static func create(isTest: Bool, peerID: PeerID, keyPair: KeyPair
	) -> AccountController {
		UserDefaults.standard.set(peerID.uuidString, forKey: Self.PeerIDKey)

		return AccountController(isTest: isTest, peerID: peerID, keyPair: keyPair)
	}

	/// Load account data from disk; factory method for `AccountController`.
	internal static func load(isTest: Bool, keyPair: KeyPair,
							  viewModel: AccountViewModelDelegate) -> AccountController? {
		guard let str = UserDefaults.standard.string(forKey: Self.PeerIDKey) else { return nil }
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

		let response = try await client.deleteAccount(
			headers: .init(userID: userID, signature: signature))

		let _ = try response.ok

		try keyPair.removeFromKeychain()

		UserDefaults.standard.removeObject(forKey: Self.PeerIDKey)
	}

	/// Retrieve an access token for API access.
	internal func getAccessToken() async throws -> String {
		let signature = try await getSignature()

		let response = try await client.getAccess(
			headers: .init(userID: userID, signature: signature))

		let body = try response.ok.body.plainText
		return try await String(collecting: body, upTo: 4096)
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
				serverURL: isTest ? URL(string: "http://192.168.0.157:8080/v1")! : //try Servers.Server3.url() :
					try Servers.Server1.url(),
				transport: URLSessionTransport()
			)
		}
	}

	/// Retrieve challenge and calculate response.
	private func getSignature() async throws -> Base64EncodedData {
		let userID = self.peerID.uuidString

		let response = try await client
			.getChallenge(headers: .init(userID: userID))

		let challengeBody = try response.accepted.body.plainText
		let base64Challenge = try await String(collecting: challengeBody,
											   upTo: 1024)

		guard let challenge = Data(base64Encoded: base64Challenge) else {
			throw createApplicationError(
				localizedDescription:
					"\(base64Challenge) is not base64-encoded.")
		}

		let signature = try keyPair.sign(message: challenge)

		return .init(signature)
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
