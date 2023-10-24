//
//  ServerChatFactory.swift
//  Peeree
//
//  Created by Christopher Kobusch on 18.04.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import MatrixSDK
import KeychainWrapper
import PeereeCore

private class CryptDelegate: MXCryptoV2MigrationDelegate {
	static let shared = CryptDelegate()

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
private func configureServerChat() {
	let options = MXSDKOptions.sharedInstance()
	options.enableCryptoWhenStartingMXSession = true
	options.disableIdenticonUseForUserAvatar = true
	options.enableKeyBackupWhenStartingMXCrypto = false // does not work with Dendrite apparently
	options.enableThreads = false
	options.authEnableRefreshTokens = false
	options.applicationGroupIdentifier = messagingAppGroup
	// it currently works without this so let's keep it that way: options.authEnableRefreshTokens = true
	options.wellknownDomainUrl = "https://\(serverChatDomain)"
	options.cryptoMigrationDelegate = CryptDelegate.shared

	MXKeyProvider.sharedInstance().delegate = EncryptionKeyManager.shared
}

/* All instance methods must be called on `ServerChatFactory.qQueue`. If they invoke a callback, that is always called on that queue as well.
 * Similarly, all static variables must be accessed from that queue. Use `use()` to get on the queue. */

/// Manages the server chat account and creates sessions (`ServerChat` instances).
public final class ServerChatFactory {

	// MARK: Static Functions

	/// This function must be called before any other. Otherwise, `ServerChatError.identityMissing` errors are thrown.
	public static func initialize(ourPeerID: PeerID,
								  dataSource: ServerChatDataSource,
								  _ completion: @escaping (ServerChatFactory) -> Void) {
		dQueue.async {
			configureServerChat()

			let factory = ServerChatFactory(peerID: ourPeerID, ds: dataSource)
			instance = factory

			completion(factory)
		}
	}

	/// Retrieves a `ServerChatFactory` for the user; `getter` will always be called on `ServerChatFactory.dQueue`.
	public static func use(_ getter: @escaping (ServerChatFactory?) -> Void) {
		dQueue.async { getter(instance) }
	}

	/// Shortcut for `use() { $0.setup() }`.
	public static func getOrSetupInstance(onlyLogin: Bool = false, _ completion: @escaping (Result<ServerChat, ServerChatError>) -> Void) {
		Self.use { factory in
			guard let factory else {
				completion(.failure(.identityMissing))
				return
			}

			factory.setup(onlyLogin: onlyLogin, completion)
		}
	}

	/// Retrieves server chat interaction singleton.
	public static func chat(_ getter: @escaping (ServerChat?) -> Void) {
		Self.use { factory in getter(factory?.serverChatController) }
	}

	// MARK: Variables

	/// Informed party of server chat.
	public weak var delegate: ServerChatDelegate?

	/// On which queue are the methods of the `conversationDelegate` invoked.
	public weak var conversationDelegate: ServerChatConversationDelegate?

	// MARK: Methods

	/// Login, create account or get readily configured `ServerChatController`.
	public func setup(onlyLogin: Bool = false, _ completion: @escaping (Result<ServerChat, ServerChatError>) -> Void) {
		if let scc = serverChatController {
			completion(.success(scc))
			return
		}

		creatingInstanceCallbacks.append(completion)
		creatingInstanceOnlyLoginRequests.append(onlyLogin)
		guard creatingInstanceCallbacks.count == 1 else { return }

		resumeSession { _ in
			// after we try to log in with the access token, proceed with password-based login
			self.loginProcess()
		}
	}

	/// Set the token to issue remote notifications.
	public func configureRemoteNotificationsDeviceToken(_ deviceToken: Data) {
		remoteNotificationsDeviceToken = deviceToken
		serverChatController?.configurePusher(deviceToken: deviceToken)
	}

	/// Closes the underlying session and invalidates the global ServerChatController instance.
	public func closeServerChat(with error: Error? = nil) {
		serverChatController?.close()
		serverChatController = nil

		delegate?.serverChatClosed(error: error)
	}

	/// Removes the server chat account permanently.
	public func deleteAccount(_ completion: @escaping (ServerChatError?) -> Void) {
		let password: String
		do {
			password = try self.passwordFromKeychain()
		} catch let error {
			let nsError = error as NSError
			if nsError.code == errSecItemNotFound && nsError.domain == NSOSStatusErrorDomain {
				// "The specified item could not be found in the keychain."
				// This most likely means that no account exists, which we could delete, so we do not report an error here.
				completion(nil)
			} else {
				completion(.fatal(error))
			}
			return
		}

		setup(onlyLogin: true) { loginResult in
			switch loginResult {
			case .failure(let error):
				wlog(Self.LogTag, "cannot login for account deletion: \(error)")
				// do not escalate the error, as we may not have an account at all
				completion(nil)

			case .success(let sc):
				guard let scc = sc as? ServerChatController else {
					flog(Self.LogTag, "cannot cast ServerChat to ServerChatController")
					completion(.fatal(unexpectedNilError()))
					return
				}

				self.isDeletingAccount = true

				scc.deleteAccount(password: password) { error in
					self.isDeletingAccount = false

					if let error = error {
						completion(error)
						return
					}

					do { try self.removePasswordFromKeychain() } catch {
						elog(Self.LogTag, "deleting password failed: \(error)")
					}
					do { try removeGenericPasswordFromKeychain(account: self.keychainAccount, service: Self.AccessTokenKeychainService) } catch {
						elog(Self.LogTag, "deleting access token failed: \(error)")
					}
					do { try removeGenericPasswordFromKeychain(account: self.keychainAccount, service: Self.RefreshTokenKeychainService) } catch {
						dlog(Self.LogTag, "deleting refresh token failed: \(error)")
					}

					self.closeServerChat()

					completion(nil)
				}
			}
		}
	}

	// MARK: - Private

	/// Creates a factory instance.
	private init(peerID: PeerID, ds: ServerChatDataSource) {
		self.peerID = peerID
		self.ds = ds
		globalRestClient.completionQueue = Self.dQueue
	}

	// MARK: Static Constants

	// Log tag.
	private static let LogTag = "ServerChatFactory"

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

	/// Singleton instance.
	private static var instance: ServerChatFactory? = nil

	/// DispatchQueue for all actions on a `ServerChatFactory`.
	private static let dQueue: DispatchQueue = DispatchQueue(label: "de.peeree.ServerChat", qos: .default)

	// MARK: Constants

	/// PeerID of the user.
	private let peerID: PeerID

	// Information provider; copied from the static variable.
	private let ds: ServerChatDataSource

	/// We need to keep a strong reference to the client s.t. it is not destroyed while requests are in flight
	private let globalRestClient = MXRestClient(homeServer: homeServerURL) { _data in
		flog(ServerChatFactory.LogTag, "matrix certificate rejected: \(String(describing: _data))")
		return false
	}

	// MARK: Variables

	/// Singleton instance.
	private var serverChatController: ServerChatController? = nil

	/// Keeps track of all invocations of `getOrSetupInstance` and is emptied once the first request completes.
	private var creatingInstanceCallbacks = [(Result<ServerChat, ServerChatError>) -> Void]()

	/// Keeps track of the `onlyLogin` parameters of all invocations of `getOrSetupInstance`.
	private var creatingInstanceOnlyLoginRequests = [Bool]()

	/// Whether account deletion request is in progress.
	private var isDeletingAccount = false

	/// APNs device token.
	private var remoteNotificationsDeviceToken: Data? = nil

	/// Matrix userId based on user's PeerID.
	private var userId: String { return peerID.serverChatUserId }

	/// Account used for all keychain operations.
	private var keychainAccount: String { return peerID.uuidString }

	// MARK: Methods


	/// Perform the login.
	private func loginProcess() {
		login { loginResult in
			switch loginResult {
			case .success(let credentials):
				self.setupInstance(with: credentials)
			case .failure(let error):
				var reallyOnlyLogin = true
				self.creatingInstanceOnlyLoginRequests.forEach { reallyOnlyLogin = reallyOnlyLogin && $0 }

				guard !reallyOnlyLogin else {
					self.reportCreatingInstance(result: .failure(error))
					return
				}

				switch error {
				case .noAccount:
					self.createAccount { createAccountResult in
						switch createAccountResult {
						case .success(let credentials):
							self.setupInstance(with: credentials)
						case .failure(let error):
							self.reportCreatingInstance(result: .failure(error))
						}
					}

				default:
					self.reportCreatingInstance(result: .failure(error))
				}
			}
		}
	}

	/// Creates an account on the chat server.
	private func createAccount(_ completion: @escaping (Result<MXCredentials, ServerChatError>) -> Void) {
		let username = peerID.serverChatUserName

		var passwordRawData: Data
		do {
			passwordRawData = try generateRandomData(length: Int.random(in: 24...26))
		} catch let error {
			completion(.failure(.fatal(error)))
			return
		}
		var passwordData = passwordRawData.base64EncodedData()

		assert(String(data: passwordData, encoding: .utf8) == passwordRawData.base64EncodedString())

		do {
			try persistPasswordInKeychain(passwordData)
			passwordData.resetBytes(in: 0..<passwordData.count)
		} catch let error {
			do {
				try removePasswordFromKeychain()
			} catch let removeError {
				wlog(Self.LogTag, "Could not remove password from keychain after insert failed: \(removeError.localizedDescription)")
			}

			completion(.failure(.fatal(error)))
			return
		}

		let registerParameters: [String: Any] = ["auth" : ["type" : kMXLoginFlowTypeDummy],
												 "username" : username,
												 "password" : passwordRawData.base64EncodedString()]

		globalRestClient.register(parameters: registerParameters) { registerResponse in
			switch registerResponse {
			case .failure(let error):
				do {
					try self.removePasswordFromKeychain()
				} catch {
					elog(Self.LogTag, "Could not remove password from keychain after failed registration: \(error.localizedDescription)")
				}
				completion(.failure(.sdk(error)))

			case .success(let responseJSON):
				guard let mxLoginResponse = MXLoginResponse(fromJSON: responseJSON) else {
					completion(.failure(.parsing("register response was no JSON: \(responseJSON)")))
					return
				}

				let credentials = MXCredentials(loginResponse: mxLoginResponse, andDefaultCredentials: nil)

				// Sanity check as done in MatrixSDK
				guard credentials.userId != nil || credentials.accessToken != nil else {
					completion(.failure(.fatal(unexpectedNilError())))
					return
				}

				do {
					try self.storeCredentialsInKeychain(credentials)
				} catch {
					completion(.failure(.fatal(error)))
					return
				}

				// this cost me at least one week: the credentials have the port stripped, because the `home_server` field in mxLoginResponse does not contain the port …
				credentials.homeServer = homeServerURL.absoluteString

				completion(.success(credentials))
			}
		}

		passwordRawData.resetBytes(in: 0..<passwordRawData.count)
	}

	/// Set always same parameters on `credentials`.
	private func prepare(credentials: MXCredentials) throws {
		// this cost me at least one week: the credentials have the port stripped, because the `home_server` field in mxLoginResponse does not contain the port …
		credentials.homeServer = homeServerURL.absoluteString

		// we currently only support one device
		credentials.deviceId = try genericPasswordFromKeychain(account: self.keychainAccount, service: Self.DeviceIDKeychainService, encoding: Self.KeychainEncoding)
	}

	/// Log into server chat account, previously created with `createAccount()`.
	private func login(completion: @escaping (Result<MXCredentials, ServerChatError>) -> Void) {
		let password: String
		do {
			password = try passwordFromKeychain()
		} catch {
			completion(.failure(.noAccount))
			return
		}

		globalRestClient.login(parameters: ["type" : kMXLoginFlowTypePassword,
											"identifier" : ["type" : kMXLoginIdentifierTypeUser, "user" : userId],
											"password" : password,
											// Patch: add the old login api parameters to make dummy login still working
											"user" : userId]) { response in
			if let error = response.error as NSError?,
			   let mxErrCode = error.userInfo[kMXErrorCodeKey] as? String {
				if mxErrCode == kMXErrCodeStringInvalidUsername {
					elog(Self.LogTag, "Our account seems to be deleted. Removing local password to be able to re-register.")
					do {
						try self.removePasswordFromKeychain()
					} catch let pwError {
						wlog(Self.LogTag, "Removing local password failed, not an issue if not existant: \(pwError.localizedDescription)")
					}
				}

				completion(.failure(.sdk(error)))
				return
			}

			guard let json = response.value else {
				elog(Self.LogTag, "Login response is nil.")
				completion(.failure(.fatal(unexpectedNilError())))
				return
			}
			guard let loginResponse = MXLoginResponse(fromJSON: json) else {
				completion(.failure(.parsing("ERROR: Cannot create login response from JSON \(json).")))
				return
			}

			let credentials = MXCredentials(loginResponse: loginResponse, andDefaultCredentials: self.globalRestClient.credentials)

			do {
				try self.storeCredentialsInKeychain(credentials)
			} catch {
				completion(.failure(.fatal(error)))
				return
			}

			// this cost me at least one week: the credentials have the port stripped, because the `home_server` field in mxLoginResponse does not contain the port …
			credentials.homeServer = homeServerURL.absoluteString

			completion(.success(credentials))
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
	private func resumeSession(_ failure: @escaping (ServerChatError) -> Void) {
		do {
			let token = try genericPasswordFromKeychain(account: keychainAccount, service:  Self.AccessTokenKeychainService, encoding: Self.KeychainEncoding)
			let creds = MXCredentials(homeServer: homeServerURL.absoluteString, userId: userId, accessToken: token)
			try self.prepare(credentials: creds)
			if let refreshToken = try? genericPasswordFromKeychain(account: keychainAccount, service: Self.RefreshTokenKeychainService, encoding: Self.KeychainEncoding) {
				creds.refreshToken = refreshToken
			}
			setupInstance(with: creds, failure)
		} catch let error {
			failure(.fatal(error))
		}
	}

	/// Sets the `serverChatController` singleton and starts the server chat session.
	private func setupInstance(with credentials: MXCredentials, _ failure: ((ServerChatError) -> Void)? = nil) {
		let restClient: MXRestClient = MXRestClient(credentials: credentials, unrecognizedCertificateHandler: { data in
			flog(Self.LogTag, "server chat certificate is not trusted.")
			self.delegate?.serverChatCertificateIsInvalid()
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

			guard let strongSelf = self, !strongSelf.isDeletingAccount else { return }

			if let error = mxError {
				flog(Self.LogTag, "server chat session became unauthenticated (soft logout: \(isSoftLogout), refresh token: \(isRefreshTokenAuth)) \(error.errcode ?? "<nil>"): \(error.error ?? "<nil>")")
				if !isSoftLogout && !isRefreshTokenAuth && error.errcode == kMXErrCodeStringUnknownToken {
					// Our token was removed, probably due to an upgrade of the Matrix server.
					// We need to remove it, s.t. password auth is again used to log in.
					do { try removeGenericPasswordFromKeychain(account: strongSelf.keychainAccount, service: Self.AccessTokenKeychainService) } catch {
						elog(Self.LogTag, "deleting access token after it became invalid failed: \(error)")
					}
					do { try removeGenericPasswordFromKeychain(account: strongSelf.keychainAccount, service: Self.RefreshTokenKeychainService) } catch {
						dlog(Self.LogTag, "deleting refresh token after it became invalid failed: \(error)")
					}
				}
			} else {
				flog(Self.LogTag, "server chat session became unauthenticated (soft logout: \(isSoftLogout), refresh token: \(isRefreshTokenAuth))")
			}

			Self.dQueue.async {
				strongSelf.closeServerChat(with: mxError?.createNSError())

				completion?()
			}
		})

		restClient.completionQueue = Self.dQueue

		let c = ServerChatController(peerID: self.peerID, restClient: restClient, dataSource: self.ds, dQueue: Self.dQueue, conversationQueue: DispatchQueue.main)
		c.conversationDelegate = self.conversationDelegate
		c.delegate = self.delegate

		c.start { error in
			Self.dQueue.async {
				if let error {
					c.close()
					if let cb = failure {
						// let the callee handle the error
						cb(.sdk(error))
					} else {
						// we finish here
						self.reportCreatingInstance(result: .failure(.sdk(error)))
					}
				} else {
					self.serverChatController = c

					// configure the pusher if server chat account didn't exist when AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken() is called
					self.remoteNotificationsDeviceToken.map { c.configurePusher(deviceToken: $0) }

					self.reportCreatingInstance(result: .success(c))
				}
			}
		}
	}

	/// Concludes registration process; must be called on the main thread!
	private func reportCreatingInstance(result: Result<ServerChat, ServerChatError>) {
		creatingInstanceCallbacks.forEach { $0(result) }
		creatingInstanceCallbacks.removeAll()
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
		do {
			// try to retrieve the password the old way
			let password = try internetPasswordFromKeychain(account: userId, url: homeServerURL)

			// migrate it to new storage
			do {
				guard let pwData = password.data(using: Self.KeychainEncoding) else {
					throw unexpectedNilError()
				}

				try persistPasswordInKeychain(pwData)
				try removeInternetPasswordFromKeychain(account: userId, url: homeServerURL)
			} catch {
				elog(Self.LogTag, "password migration failed: \(error)")
			}

			return password
		} catch {
			// the new way
			return try genericPasswordFromKeychain(account: keychainAccount, service: Self.ServerChatPasswordKeychainService, encoding: Self.KeychainEncoding)
		}
	}

	/// force-delete local account information. Only use as a last resort!
	private func removePasswordFromKeychain() throws {
		do {
			try removeInternetPasswordFromKeychain(account: userId, url: homeServerURL)
		} catch {
			try removeGenericPasswordFromKeychain(account: keychainAccount, service: Self.ServerChatPasswordKeychainService)
		}
	}
}
