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

	// MARK: Methods

	/// Call this as soon as possible.
	public init(
		config: AccountModuleConfig, viewModel: AccountViewModelDelegate) {
		self.viewModel = viewModel
		self.config = config
	}

	/// Retrieves the singleton.
	public func use() throws -> AccountController? {
		if let i = self.instance {
			return i
		}

		let keyPair = KeyPair(
			fromKeychainWithTag: self.privateKeyTag,
			algorithm: PeereeIdentity.KeyAlgorithm,
			size: PeereeIdentity.KeySize)

		if let ac = AccountController.load(
			isTest: isTest, keyPair: keyPair, viewModel: self.viewModel) {
			self.setInstance(ac)
			return ac
		} else { return nil }
	}

	/// Creates a new `PeereeIdentity` for the user.
	public func createOrRecoverAccount(using recoveryCode: String?)
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
			let oldKeyPair = KeyPair(fromKeychainWithTag: self.privateKeyTag,
				algorithm: PeereeIdentity.KeyAlgorithm,
				size: PeereeIdentity.KeySize)
			try? oldKeyPair.removeFromKeychain()

			// this will add the pair to the keychain,
			// from where it is read later by the constructor
			keyPair = try KeyPair(tag: self.privateKeyTag,
				algorithm: PeereeIdentity.KeyAlgorithm,
				size: PeereeIdentity.KeySize)

			let publicKeyData = try keyPair.publicKey.externalRepresentation()

			// TODO: we need to currently pass this, since swift server is broken
			let channel = Components.Schemas.OutOfBandChannel(
				channel: .init(name: "Bla"),
				endpoint: "Blub"
			)

			let response: Operations.PostAccount.Output

			if let recoveryCode {
				response = try await client()
					.postAccount(
						query: .init(publicKey: .init(publicKeyData)),
						headers: .init(recoveryCode: recoveryCode))

			} else {
				response = try await client()
					.postAccount(
						query: .init(publicKey: .init(publicKeyData)),
						body: .json(channel))
			}

			let account: Components.Schemas.Account

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
				account = try response.body.json
			case .ok(let response):
				account = try response.body.json
			}

			guard let peerID = UUID(uuidString: account.userID) else {
				throw makeProgrammingError("Malformed peerID \(account.userID)")
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

	// From where to get JKS
	private var jwksURL: URL {
		get throws {
			// TODO: host JKS on another party
			guard let result = URL(string:
				self.isTest ? "https://www.peeree.de/.well-known/jwks-test" :
					"https://www.peeree.de/.well-known/jwks") else {
				throw unexpectedNilError()
			}

			return result
		}
	}

	// MARK: Variables

	/// Whether the test backend should be used.
	private let config: AccountModuleConfig

	/// Whether the test backend should be used.
	private var isTest: Bool {
		switch self.config {
		case .production:
			return false
		case .testing(_):
			return true
		}
	}

	/// Whether the test backend should be used.
	private var privateKeyTag: Data {
		switch self.config {
		case .production:
			return Self.PrivateKeyTag.data(using: .utf8)!
		case .testing(let testConfig):
			return testConfig.privateKeyTag.data(using: .utf8)!
		}
	}

	private var apiURL: URL {
		get throws {
			isTest ? try Servers.Server2.url() :
			try Servers.Server1.url()
		}
	}

	/// Network client for IdP API access.
	private func client() throws -> Client {
		Client(
			serverURL: try self.apiURL,
			transport: URLSessionTransport()
		)
	}

	/// Singleton instance of this class.
	private var instance: AccountController?

	/// Verifies the identity of other peers.
	private var tokenVerifier: TokenVerifier?

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

extension AccountControllerFactory {
	public func getIdentityToken(of peerID: PeerID)
	async throws -> ArraySlice<UInt8> {
		guard let ac = try self.use() else {
			throw AccountError.noAccount
		}

		return try await ac.getIdentityToken(of: peerID)
	}

	fileprivate func initTokenVerfifier() async throws -> TokenVerifier {
		if let v = self.tokenVerifier {
			return v
		} else {
			let verifier = try TokenVerifier(issuerURL: try self.apiURL)

			// TODO: cache JKS
			try await verifier.initialize(from: try self.jwksURL)
			self.tokenVerifier = verifier
			return verifier
		}
	}
	
	public func verify(_ peerID: PeereeCore.PeerID,
					   publicKey: any KeychainWrapper.AsymmetricPublicKey,
					   identityToken: Data?) async throws {
		// verify that the token comes from the Peeree server

		let verifier = try await self.initTokenVerfifier()

		let token: IdentityTokenJWT

		if let identityToken {
			do {
				token = try await verifier.verifyIdentityToken(identityToken)
			} catch {
				wlog(
					Self.LogTag,
					"Verification of identity token retrieved via Bluetooth" +
					"failed; fetching it from server.")
				
				let identityToken = try await self.getIdentityToken(of: peerID)

				token = try await verifier.verifyIdentityToken(Data(identityToken))
			}
		} else {
			let identityToken = try await self.getIdentityToken(of: peerID)

			token = try await verifier.verifyIdentityToken(Data(identityToken))
		}

		guard let tokenPublicKeyData = token.pbk.value.data(using: .utf8),
			  let tokenPublicKey = Data(base64Encoded: tokenPublicKeyData) else
		{
			throw unexpectedNilError()
		}

		// check if public key matches the one from the token

		guard try publicKey.externalRepresentation() == tokenPublicKey else {
			throw createApplicationError(
				localizedDescription: NSLocalizedString(
				"Someone is not who they say they are.",
				comment: "Public key mismatch"))
		}
	}
}

extension AccountControllerFactory: PeereeCore.Authenticator {
	public func accessToken() async throws -> AccessTokenData {
		guard let ac = try self.use() else {
			throw AccountError.noAccount
		}

		let verifier = try await initTokenVerfifier()

		let accessToken = try await ac.getAccessToken()

		let payload = try await verifier.verifyAccessToken(accessToken)

		guard let tokenString = String(
			data: Data(accessToken), encoding: .utf8) else {
			throw unexpectedNilError()
		}

		return .init(accessToken: tokenString, expiresAt: payload.exp.value)
	}
}
