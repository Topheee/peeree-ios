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

	// MARK: Methods

	/// Call this as soon as possible.
	public init(viewModel: AccountViewModelDelegate, isTest: Bool) {
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
	public func createAccount()
	async throws -> (AccountController, ChatAccount) {
		if instance != nil {
			throw AccountError.accountAlreadyExists
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

			// TODO: we need to currently pass this, since swift server is broken
			let channel = Components.Schemas.OutOfBandChannel(
				channel: .init(name: "Bla"),
				endpoint: "Blub"
			)

			let response = try await client()
				.postAccount(query: .init(publicKey: .init(publicKeyData)),
							 body: .json(channel))

			switch response {
			case .badRequest(let response):
				try await handle(response, logTag: Self.LogTag)
			case .tooManyRequests(let response):
				try await handle(response, logTag: Self.LogTag)
			case .internalServerError(let response):
				try await handle(response, logTag: Self.LogTag)
			case .undocumented(statusCode: let statusCode, let payload):
				try await handle(statusCode, payload, logTag: Self.LogTag)
			case .created(let response):
				let account = try response.body.json
				guard let peerID = UUID(uuidString: account.userID) else {
					try programmingError("Malformed peerID \(account.userID)")
				}
				let a = AccountController.create(
					isTest: isTest, peerID: peerID, keyPair: keyPair)
				self.setInstance(a)
				self.reportCreatingInstance(result: .success(a), vm: vm)

				let chatAccount = ChatAccount(
					userID: account.chatAccount.userID,
					accessToken: account.chatAccount.accessToken,
					homeServer: account.chatAccount.serverURL,
					deviceID: account.chatAccount.deviceID,
					initialPassword: account.chatAccount.initialPassword)

				Notification.Name.accountCreated
					.post(on: a,
						  userInfo: [PeerID.NotificationInfoKey : peerID])

				return (a, chatAccount)
			}
		} catch let error {
			reportCreatingInstance(result: .failure(error), vm: vm)
			if let apiError = error as? OpenAPIRuntime.ClientError {
				// not beautiful, but easiest way to show transport errors
				throw apiError.underlyingError
			} else {
				throw error
			}
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

		do {
			try await ac.deleteAccount()
		} catch {
			Task { @MainActor in
				vm.accountExists = .on
			}
			throw error
		}

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

		let peerID = ac.peerID

		Task { @MainActor in
			viewModel.userPeerID = peerID
			viewModel.accountExists = .on
		}
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
			throw AccountError.noAccount
		}

		return try await ac.getAccessToken()
	}
}
