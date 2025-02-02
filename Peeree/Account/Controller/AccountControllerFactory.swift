//
//  AccountControllerFactory.swift
//  PeereeServer
//
//  Created by Christopher Kobusch on 18.10.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

// Platform Dependencies
import Foundation

// Internal Dependencies
import PeereeCore

// External Dependencies
import KeychainWrapper
import OpenAPIURLSession
import OpenAPIRuntime

/// Names of notifications sent by `AccountControllerFactory`.
extension Notification.Name {

	/// Notifications regarding identity management.
	public static
	let accountCreated = Notification.Name("de.peeree.accountCreated")

	/// Notifications regarding identity management.
	public static
	let accountDeleted = Notification.Name("de.peeree.accountDeleted")
}

/// Responsible for creating an ``AccountController`` singleton.
public actor AccountControllerFactory {

	/// Whether the test backend should be used.
	private let isTest: Bool

	/// Network client for IdP API access.
	private func client() throws -> Client {
		Client(
			serverURL: isTest ? try Servers.Server2.url() :
				try Servers.Server1.url(),
			transport: URLSessionTransport()
		)
	}

	/// Handle API error.
	private func handle(
		_ response: Components.Responses.ClientSideErrorResponse
	) throws -> Never {
		throw createApplicationError(
			localizedDescription: "Programming error.")
	}

	/// Handle API error.
	private func handle(
		_ response: Components.Responses.InvalidSignatureResponse
	) throws -> Never {
		throw createApplicationError(
			localizedDescription: "Severe Programming error.")
	}

	/// Handle API error.
	private func handle(_ response: Components.Responses.RateLimitResponse
	) throws -> Never {
		throw createApplicationError(
			localizedDescription: "Too many requests.")
	}

	/// Handle API error.
	private func handle(
		_ response: Components.Responses.ServerSideErrorResponse
	) throws -> Never {
		throw createApplicationError(localizedDescription: "Server error.")
	}

	/// Handle API error.
	private func handle(
		_ statusCode: Int, _ payload: OpenAPIRuntime.UndocumentedPayload
	) throws -> Never {
		// TODO: localize
		throw createApplicationError(
			localizedDescription: "Unknown IdP error \(statusCode).")
	}

	// MARK: Methods

	/// Call this as soon as possible.
	public init(viewModel: AccountViewModelDelegate, isTest: Bool = false) {
		self.viewModel = viewModel
		self.isTest = isTest
	}

	/// Retrieves the singleton.
	public func use() throws -> AccountController? {
		if let i = self.instance {
			return i
		}

		let keyPair = KeyPair(
			fromKeychainWithPrivateTag: Self.PrivateKeyTag,
			publicTag: Self.PublicKeyTag,
			algorithm: PeereeIdentity.KeyAlgorithm,
			size: PeereeIdentity.KeySize)

		if let ac = AccountController.load(
			isTest: isTest, keyPair: keyPair, viewModel: self.viewModel) {
			self.setInstance(ac)
			return ac
		} else { return nil }
	}

	/// Creates a new `PeereeIdentity` for the user.
	public func createAccount() async throws -> AccountController {
		if let i = instance {
			return i
		}

		let vm = self.viewModel

		Task { @MainActor in
			vm.accountExists = .turningOn
		}

		// generate our asymmetric key pair
		let keyPair: KeyPair
		do {
			// try to remove the old key, just to be sure
			let oldKeyPair = KeyPair(
				fromKeychainWithPrivateTag: Self.PrivateKeyTag,
				publicTag: Self.PublicKeyTag,
				algorithm: PeereeIdentity.KeyAlgorithm,
				size: PeereeIdentity.KeySize)
			try? oldKeyPair.removeFromKeychain()

			// this will add the pair to the keychain,
			// from where it is read later by the constructor
			keyPair = try KeyPair(
				privateTag: Self.PrivateKeyTag, publicTag: Self.PublicKeyTag,
				algorithm: PeereeIdentity.KeyAlgorithm,
				size: PeereeIdentity.KeySize, persistent: true)

			let publicKeyData = try keyPair.publicKey.externalRepresentation()

			let response = try await client()
				.postAccount(query: .init(publicKey: .init(publicKeyData)))

			switch response {
			case .badRequest(let response):
				try self.handle(response)
			case .tooManyRequests(let response):
				try self.handle(response)
			case .internalServerError(let response):
				try self.handle(response)
			case .undocumented(statusCode: let statusCode, let payload):
				try self.handle(statusCode, payload)
			case .created(let response):
				let account = try response.body.json
				guard let peerID = UUID(uuidString: account.userID) else {
					throw createApplicationError(
						localizedDescription:
							"Malformed peerID \(account.userID)")
				}
				let a = AccountController.create(
					isTest: isTest, peerID: peerID, keyPair: keyPair,
					viewModel: vm)
				self.setInstance(a)
				self.reportCreatingInstance(result: .success(a), vm: vm)

				Notification.Name.accountCreated
					.post(on: a,
						  userInfo: [PeerID.NotificationInfoKey : peerID])

				return a
			}
		} catch let error {
			reportCreatingInstance(result: .failure(error), vm: vm)
			throw error
		}
	}

	/// Permanently delete this identity.
	/// Do not use this `AccountController` instance after this completes successfully!
	public func deleteAccount() async throws {
		guard let ac = instance else { return }

		let vm = self.viewModel
		Task { @MainActor in
			vm.accountExists = .turningOff
		}

		try await ac.deleteAccount()

		await ac.clearLocalData()

		self.instance = nil

		Task { @MainActor in
			vm.userPeerID = nil
			vm.accountExists = .off
		}

		Notification.Name.accountDeleted.post(on: self)
	}

	// MARK: Private

	// MARK: Static Constants

	// Log tag.
	private static let LogTag = "Account"

	/// Keychain property.
	private static let PrivateKeyTag = "com.peeree.keys.restkey.private"
		.data(using: .utf8)!

	/// Keychain property.
	private static let PublicKeyTag = "com.peeree.keys.restkey.public"
		.data(using: .utf8)!

	// MARK: Variables

	/// Singleton instance of this class.
	private var instance: AccountController?

	@MainActor
	private let viewModel: AccountViewModelDelegate

	// MARK: Static Functions

	/// Establish the singleton instance.
	private func setInstance(_ ac: AccountController) {
		instance = ac
	}

	/// Concludes registration process; must be called on `dQueue`!
	private func reportCreatingInstance(
		result: Result<AccountController, Error>,
		vm: any AccountViewModelDelegate) {
		Task { @MainActor in
			switch result {
			case .success(_):
				vm.accountExists = .on
			case .failure(_):
				vm.accountExists = .off
			}
		}
	}
}

extension AccountControllerFactory: PeereeCore.Authenticator {
	public func accessToken() async throws -> String {
		guard let ac = try self.use() else {
			throw createApplicationError(
				localizedDescription: "Tried to access API without account.")
		}

		return try await ac.getAccessToken()
	}
}
