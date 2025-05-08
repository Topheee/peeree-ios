//
//  ServerChatFactory.swift
//  Peeree
//
//  Created by Christopher Kobusch on 18.04.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
@preconcurrency import MatrixSDK
import KeychainWrapper
import PeereeCore

private class CryptDelegate: MXCryptoV2MigrationDelegate {
	init() {
		needsVerificationUpgrade = true
	}

	var needsVerificationUpgrade: Bool {
		didSet {
			dlog(Self.LogTag, "needsVerificationUpgrade set to \(needsVerificationUpgrade).")
		}
	}

	// Log tag.
	private static let LogTag = "CryptDelegate"
}

/// Must be called as soon as possible.
private func configureServerChat(cryptDelegate: CryptDelegate) {
	let options = MXSDKOptions.sharedInstance()
	options.enableCryptoWhenStartingMXSession = true
	options.disableIdenticonUseForUserAvatar = true
	options.enableKeyBackupWhenStartingMXCrypto = false // does not work with Dendrite apparently
	options.enableThreads = false
	options.authEnableRefreshTokens = false
	options.applicationGroupIdentifier = messagingAppGroup
	// it currently works without this so let's keep it that way: options.authEnableRefreshTokens = true
	options.wellknownDomainUrl = "https://www.peeree.de"
	options.cryptoMigrationDelegate = cryptDelegate

	MXKeyProvider.sharedInstance().delegate = EncryptionKeyManager()
}

/* All instance methods must be called on `ServerChatFactory.qQueue`. If they invoke a callback, that is always called on that queue as well.
 * Similarly, all static variables must be accessed from that queue. Use `use()` to get on the queue. */

/// Manages the server chat account and creates sessions (`ServerChat` instances).
@ChatActor
public final class ServerChatFactory {

	/// Takes a freshly created account.
	public convenience
	init(account: ServerChatAccount, ourPeerID peerID: PeerID,
		 delegate: ServerChatDelegate?,
		 conversationDelegate: (any ServerChatViewModelDelegate)?
	) async throws {
		self.init(ourPeerID: peerID, delegate: delegate,
				  conversationDelegate: conversationDelegate)

		guard let passwordData = account.initialPassword
			.data(prefixedEncoding: .utf8) else {
			throw ServerChatError.fatal(ServerChatError
				.parsing("Invalid initial password."))
		}

		do {
			try persistPasswordInKeychain(passwordData)
		} catch let error {
			do {
				try removePasswordFromKeychain()
			} catch let removeError {
				wlog(Self.LogTag,
					 "Could not remove password from keychain after insert failed: \(removeError.localizedDescription)")
			}

			throw ServerChatError.fatal(error)
		}

		UserDefaults.standard.set(
			account.homeServer, forKey: Self.HomeServerURLKey)

		try self.storeCredentialsInKeychain(account.credentials)

		try await self.changePassword(of: account)
	}

	// MARK: Variables

	/// Informed party of server chat module.
	public weak var delegate: ServerChatDelegate?

	/// Informed party about server chats.
	public weak var conversationDelegate: (any ServerChatViewModelDelegate)?

	// MARK: Methods

	/// Creates a factory instance.
	public init(ourPeerID peerID: PeerID,
				delegate: ServerChatDelegate?,
				conversationDelegate: (any ServerChatViewModelDelegate)?) {
		self.peerID = peerID
		self.delegate = delegate
		self.conversationDelegate = conversationDelegate
		configureServerChat(cryptDelegate: self.cryptDelegate)
	}

	/// Retrieves server chat interaction singleton.
	public func chat() async -> ServerChat? {
		return self.serverChatController
	}

	/// Login, create account or get readily configured `ServerChatController`.
	public func use(with dataSource: ServerChatDataSource)
	async throws -> ServerChat {
		if let scc = self.serverChatController { return scc }

		do {
			return try await resumeSession(dataSource: dataSource)
		} catch {
			// after we try to log in with the access token, proceed with password-based login
			return try await self.loginProcess(dataSource: dataSource)
		}
	}

	/// Set the token to issue remote notifications.
	public func configureRemoteNotificationsDeviceToken(_ deviceToken: Data) async {
		remoteNotificationsDeviceToken = deviceToken
		await serverChatController?.configurePusher(deviceToken: deviceToken)
	}

	/// Closes the underlying session and invalidates the global ServerChatController instance.
	public func closeServerChat(with error: Error? = nil) async {
		serverChatController?.close()
		serverChatController = nil

		Task { await self.delegate?.serverChatClosed(error: error) }
	}

	/// Removes the server chat account permanently.
	public func deleteAccount() async throws {
		let password: String
		do {
			password = try self.passwordFromKeychain()
		} catch let error {
			let nsError = error as NSError
			if nsError.code == errSecItemNotFound && nsError.domain == NSOSStatusErrorDomain {
				// "The specified item could not be found in the keychain."
				// This most likely means that no account exists, which we could delete, so we do not report an error here.
				return
			} else {
				throw ServerChatError.fatal(error)
			}
		}

		guard let scc = self.serverChatController else {
			throw ServerChatError.fatal(unexpectedNilError())
		}

		try await scc.deleteAccount(password: password)

		do { try self.removePasswordFromKeychain() } catch {
			elog(Self.LogTag, "deleting password failed: \(error)")
		}

		do {
			try removeGenericPasswordFromKeychain(
				account: self.keychainAccount,
				service: Self.AccessTokenKeychainService)
		} catch {
			elog(Self.LogTag, "deleting access token failed: \(error)")
		}

		do {
			try removeGenericPasswordFromKeychain(
				account: self.keychainAccount,
				service: Self.RefreshTokenKeychainService)
		} catch {
			dlog(Self.LogTag, "deleting refresh token failed: \(error)")
		}

		await self.closeServerChat()
	}

	// MARK: - Private

	// MARK: Static Constants

	/// Log tag.
	private static let LogTag = "ServerChatFactory"

	/// Home server URL key in user defaults.
	private static let HomeServerURLKey = "HomeServerURLKey"

	/// Matrix refresh token service attribute in keychain.
	private static let RefreshTokenKeychainService = "RefreshTokenKeychainService"

	/// Matrix access token service attribute in keychain.
	private static let AccessTokenKeychainService = "AccessTokenKeychainService"

	/// Matrix deviceId service attribute in keychain.
	private static let DeviceIDKeychainService = "DeviceIDKeychainService"

	/// Matrix account password service attribute in keychain.
	private static let ServerChatPasswordKeychainService = "ServerChatPasswordKeychainService"

	/// Encoding used to store keychain values.
	private static let KeychainEncoding = String.Encoding.utf8

	// MARK: Static Variables

	// MARK: Constants

	/// PeerID of the user.
	private let peerID: PeerID

	/// Necessary for Matrix migrations.
	private let cryptDelegate = CryptDelegate()

	// MARK: Variables

	/// Singleton instance.
	private var serverChatController: ServerChatController? = nil

	/// APNs device token.
	private var remoteNotificationsDeviceToken: Data? = nil

	/// Matrix userId based on user's PeerID.
	private var userId: String {
		get throws { return peerID.serverChatUserId(try self.homeServerURL) }
	}

	/// Account used for all keychain operations.
	private var keychainAccount: String { return peerID.uuidString }

	// MARK: Methods


	/// Perform the login.
	private func loginProcess(dataSource: ServerChatDataSource)
	async throws -> ServerChatController {
		let credentials = try await login()
		return try await self.setupInstance(with: credentials,
											dataSource: dataSource)
	}

	/// Creates an account on the chat server.
	/// - Throws: `ServerChatError`
	private func changePassword(of account: ServerChatAccount) async throws {
		// In case we need to restore the old password.
		guard let oldPassword = account.initialPassword
			.data(using: .utf8) else {
			throw ServerChatError.fatal(makeProgrammingError(
				"initial password not utf8-compatible"))
		}

		var passwordRawData: Data
		do {
			passwordRawData = try generateRandomData(length: Int.random(in: 24...26))
		} catch let error {
			throw ServerChatError.fatal(error)
		}

		var passwordData = passwordRawData.base64EncodedData()

		defer {
			passwordData.resetBytes(in: 0..<passwordData.count)
			passwordRawData.resetBytes(in: 0..<passwordRawData.count)
		}

		assert(String(data: passwordData, encoding: .utf8) == passwordRawData.base64EncodedString())

		do {
			try self.removePasswordFromKeychain()
			try self.persistPasswordInKeychain(passwordData)
		} catch let error {
			self.restore(oldPassword: oldPassword)
			throw ServerChatError.fatal(error)
		}

		let changePasswordClient = MXRestClient(credentials: account.credentials)

		return try await withCheckedThrowingContinuation { continuation in
			changePasswordClient.changePassword(
				from: account.initialPassword,
				to: passwordRawData.base64EncodedString(),
				logoutDevices: true) { response in

				switch response {
				case .failure(let error):
					defer {
						continuation
							.resume(throwing: ServerChatError.sdk(error))
					}

					self.restore(oldPassword: oldPassword)
				case .success:
					continuation.resume()
				}
			}
		}
	}

	/// Writes `oldPassword` to the keychain.
	private func restore(oldPassword: Data) {
		do {
			try? self.removePasswordFromKeychain()
			try self.persistPasswordInKeychain(oldPassword)
		} catch {
			flog(Self.LogTag, "Could not remove password from"
				 + " keychain after failed registration: "
				 + error.localizedDescription)
		}
	}

	/// Set always same parameters on `credentials`.
	private func prepare(credentials: MXCredentials) throws {
		// this cost me at least one week: the credentials have the port stripped, because the `home_server` field in mxLoginResponse does not contain the port …
		// TODO: credentials.homeServer = homeServerURL.absoluteString

		// we currently only support one device
		credentials.deviceId = try genericPasswordFromKeychain(account: self.keychainAccount, service: Self.DeviceIDKeychainService, encoding: Self.KeychainEncoding)
	}

	/// The full home server URL.
	private var homeServerURL: URL {
		get throws {
			if let homeServer = UserDefaults.standard
				.string(forKey: Self.HomeServerURLKey) {
				if let url = URL(string: homeServer) {
					return url
				} else {
					throw makeProgrammingError("home server URL unparsable")
				}
			} else {
				throw makeProgrammingError("no home server URL set")
			}
		}
	}

	/// Log into server chat account, previously created with `createAccount()`.
	private func login() async throws -> MXCredentials {
		let password: String
		do {
			password = try passwordFromKeychain()
		} catch {
			let nsError = error as NSError

			if nsError.code == errSecItemNotFound
				&& nsError.domain == NSOSStatusErrorDomain {
				throw ServerChatError.noAccount
			} else {
				throw error
			}
		}

		let hsURL = try self.homeServerURL
		let ourUserId = try self.userId

		// We need to keep a strong reference to the client s.t. it is not
		// destroyed while requests are in flight
		let bootstrapMXClient = MXRestClient(homeServer: hsURL)
		{ _data in
			flog(ServerChatFactory.LogTag,
				 "matrix certificate rejected: \(String(describing: _data))")
			return false
		}
		bootstrapMXClient.completionQueue = ChatActor.dQueue

		return try await withCheckedThrowingContinuation(isolation: ChatActor.shared) { continuation in
			let parameters: [String : Any] = [
				"type" : kMXLoginFlowTypePassword,
				"identifier" : ["type" : kMXLoginIdentifierTypeUser,
								"user" : ourUserId],
				"password" : password,
				// Patch: add the old login api parameters to make dummy login working
				"user" : ourUserId
			]

			bootstrapMXClient.login(parameters: parameters) { response in
				if let error = response.error as NSError? {
					defer {
						continuation.resume(throwing: ServerChatError.sdk(error))
					}

					if let mxErrCode = error.userInfo[kMXErrorCodeKey] as? String {
						if mxErrCode == kMXErrCodeStringInvalidUsername {
							elog(Self.LogTag, "Our account seems to be deleted."
								 + " Removing password to be able to re-register.")
							do {
								try self.removePasswordFromKeychain()
							} catch let pwError {
								wlog(Self.LogTag, "Removing local password failed."
									 + " This is not an issue if not existant."
									 + pwError.localizedDescription)
							}
						}
					}

					return
				}

				guard let json = response.value else {
					elog(Self.LogTag, "Login response is nil.")
					continuation.resume(throwing: ServerChatError
						.fatal(unexpectedNilError()))
					return
				}
				guard let loginResponse = MXLoginResponse(fromJSON: json) else {
					continuation.resume(throwing: ServerChatError.parsing(
						"ERROR: Cannot create login response from JSON \(json)."))
					return
				}

				let credentials = MXCredentials(
					loginResponse: loginResponse,
					andDefaultCredentials: nil)

				do {
					try self.storeCredentialsInKeychain(credentials)
				} catch {
					continuation.resume(
						throwing: ServerChatError.fatal(error))
					return
				}

				// this cost me at least one week: the credentials have the
				// port stripped, because the `home_server` field in
				// mxLoginResponse does not contain the port …
				credentials.homeServer = hsURL.absoluteString

				continuation.resume(returning: credentials)
			}
		}
	}

	/// Puts the access token and device ID into the keychain, and the refresh token as well (if available).
	private func storeCredentialsInKeychain(_ credentials: MXCredentials) throws {
		guard let accessToken = credentials.accessToken,
			  let deviceId = credentials.deviceId else {
			throw unexpectedNilError()
		}

		// possible old tokens are automatically overridden
		try persistGenericPasswordInKeychain(accessToken, account: keychainAccount, service: Self.AccessTokenKeychainService, encoding: Self.KeychainEncoding)
		try persistGenericPasswordInKeychain(deviceId, account: keychainAccount, service: Self.DeviceIDKeychainService, encoding: Self.KeychainEncoding)

		// the refresh token might be missing
		credentials.refreshToken.map {
			try? persistGenericPasswordInKeychain($0, account: keychainAccount, service: Self.RefreshTokenKeychainService, encoding: Self.KeychainEncoding)
		}
	}

	/// Tries to create a new session with a previous access token; prevents from creating new devices in Dendrite.
	/// - Throws: `ServerChatError`
	private func resumeSession(dataSource: ServerChatDataSource)
	async throws -> ServerChatController {
		do {
			let token = try genericPasswordFromKeychain(
				account: self.keychainAccount,
				service: Self.AccessTokenKeychainService,
				encoding: Self.KeychainEncoding)

			let creds = MXCredentials(
				homeServer: try self.homeServerURL.absoluteString,
				userId: try self.userId, accessToken: token)

			try self.prepare(credentials: creds)
			if let refreshToken = try? genericPasswordFromKeychain(account: keychainAccount, service: Self.RefreshTokenKeychainService, encoding: Self.KeychainEncoding) {
				creds.refreshToken = refreshToken
			}

			return try await setupInstance(with: creds, dataSource: dataSource)
		} catch let error as ServerChatError {
			throw error
		} catch let error {
			throw ServerChatError.fatal(error)
		}
	}

	/// Sets the `serverChatController` singleton and starts the server chat session.
	/// - Throws: `ServerChatError`
	private func setupInstance(with credentials: MXCredentials,
							   dataSource: ServerChatDataSource
	) async throws -> ServerChatController {

		let restClient: MXRestClient = MXRestClient(credentials: credentials, unrecognizedCertificateHandler: { data in
			flog(Self.LogTag, "server chat certificate is not trusted.")
			Task { await self.delegate?.serverChatCertificateIsInvalid() }
			return false
		}, persistentTokenDataHandler: { callback in
			dlog(Self.LogTag, "server chat persistentTokenDataHandler was called.")
			// Block called when the rest client needs to check the persisted refresh token data is valid and optionally persist new refresh data to disk if it is not.
			callback?([credentials]) { shouldPersist in
				// credentials (access and refresh token) changed during refresh
				guard shouldPersist else { return }

				// The credentials are passed by reference, so their token properties have changed by now.
				credentials.accessToken.map { try? persistGenericPasswordInKeychain($0, account: self.keychainAccount, service:  Self.AccessTokenKeychainService, encoding: Self.KeychainEncoding) }
				credentials.refreshToken.map { try? persistGenericPasswordInKeychain($0, account: self.keychainAccount, service: Self.RefreshTokenKeychainService, encoding: Self.KeychainEncoding) }
			}
		}, unauthenticatedHandler: { [weak self] mxError, isSoftLogout, isRefreshTokenAuth, completion in
			// Block called when the rest client has become unauthenticated(E.g. refresh failed or server invalidated an access token).
			// A client that receives such a response can try to refresh its access token, if it has a refresh token available. If it does not have a refresh token available, or refreshing fails with soft_logout: true, the client can acquire a new access token by specifying the device ID it is already using to the login API.

			guard let strongSelf = self else { return }

			guard let mxError else {
				flog(Self.LogTag, "server chat session became unauthenticated"
					 + " (soft logout: \(isSoftLogout), refresh token:"
					 + " \(isRefreshTokenAuth))")
				return
			}

			flog(Self.LogTag, "server chat session became unauthenticated"
				 + " (soft logout: \(isSoftLogout), refresh token: "
				 + "\(isRefreshTokenAuth)) \(mxError.errcode ?? "<nil>"): "
				 + "\(mxError.error ?? "<nil>")")

			if !isSoftLogout && !isRefreshTokenAuth
				&& mxError.errcode == kMXErrCodeStringUnknownToken {
				let error = mxError.createNSError()

				Task {
					// Our token was removed, probably due to an upgrade of the Matrix server.
					// We need to remove it, s.t. password auth is again used to log in.
					do {
						try removeGenericPasswordFromKeychain(
							account: strongSelf.keychainAccount,
							service: Self.AccessTokenKeychainService)
					} catch {
						elog(Self.LogTag, "deleting access token after it"
							 + " became invalid failed: \(error)")
					}

					do {
						try removeGenericPasswordFromKeychain(
							account: strongSelf.keychainAccount,
							service: Self.RefreshTokenKeychainService)
					} catch {
						dlog(Self.LogTag, "deleting refresh token after it"
							 + " became invalid failed: \(error)")
					}

					await strongSelf.closeServerChat(with: error)
				}
			}

			// TODO: this must probably be called inside the Task above
			completion?()
		})

		restClient.completionQueue = ChatActor.dQueue

		let c = ServerChatController(
			peerID: self.peerID, restClient: restClient,
			dataSource: dataSource)

		let _ = await Task { @ChatActor in
			c.conversationDelegate = self.conversationDelegate
			c.delegate = self.delegate
		}.value

		do {
			try await c.start()

			self.serverChatController = c

			// configure the pusher if server chat account didn't exist when
			// AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken()
			// is called
			if let token = self.remoteNotificationsDeviceToken {
				await c.configurePusher(deviceToken: token)
			}

			return c
		} catch {
			c.close()
			throw ServerChatError.sdk(error)
		}
	}

	// MARK: Keychain Access

	/// Writes the `password` into the keychain as an internet password.
	private func persistPasswordInKeychain(_ password: Data) throws {
		// while it is tempting to store the value as an internet password, the URL and especially it's port are part of the primary key
		// since we belive this is subject to change in the future, we just store the password as a generic password
		// note that previously the password was indeed stored as an internet password, although lots of the primary key attributes where not set
		try persistGenericPasswordInKeychain(password, account: keychainAccount, service: Self.ServerChatPasswordKeychainService)
	}

	/// Retrieves our account's password from the keychain.
	private func passwordFromKeychain() throws -> String {
		return try genericPasswordFromKeychain(
			account: keychainAccount,
			service: Self.ServerChatPasswordKeychainService,
			encoding: Self.KeychainEncoding)
	}

	/// force-delete local account information. Only use as a last resort!
	private func removePasswordFromKeychain() throws {
		try removeGenericPasswordFromKeychain(
			account: keychainAccount,
			service: Self.ServerChatPasswordKeychainService)
	}
}
