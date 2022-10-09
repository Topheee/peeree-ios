//
//  ServerChatFactory.swift
//  Peeree
//
//  Created by Christopher Kobusch on 18.04.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import MatrixSDK

/* All instance methods must be called on `ServerChatFactory.qQueue`. If they invoke a callback, that is always called on that queue as well. */

/// Manages the server chat account and creates sessions (`ServerChat` instances).
public class ServerChatFactory {

	// MARK: Static Variables

	/// Informed party.
	static var delegate: ServerChatDelegate? = nil {
		didSet {
			use { factory in
				factory?.serverChatController?.delegate = delegate
			}
		}
	}

	/// APNs device token.
	static var remoteNotificationsDeviceToken: Data? = nil

	// MARK: Static Functions

	/// Retrieves server chat interaction singleton.
	public static func chat(_ getter: @escaping (ServerChat?) -> Void) {
		Self.use { factory in getter(factory?.serverChatController) }
	}

	/// Retrieves already logged in instance, or creates a new one by logging in.
	public static func getOrSetupInstance(onlyLogin: Bool = false, _ completion: @escaping (Result<ServerChat, ServerChatError>) -> Void) {
		Self.use { factory in
			guard let f = factory else {
				completion(.failure(.identityMissing))
				return
			}

			if let scc = f.serverChatController {
				completion(.success(scc))
			} else {
				f.setup(onlyLogin: onlyLogin, completion)
			}
		}
	}

	/// Retrieves a `ServerChatFactory` for the user.
	public static func use(_ getter: @escaping (ServerChatFactory?) -> Void) {
		AccountController.use({ ac in
			guard let i = instance, i.peerID == ac.peerID else {
				let newInstance = ServerChatFactory(peerID: ac.peerID)
				instance = newInstance
				getter(newInstance)
				return
			}

			getter(i)
		}, { getter(nil) })
	}

	// MARK: Methods

	/// Closes the underlying session and invalidates the global ServerChatController instance.
	public static func close() {
		use { $0?.closeServerChat() }
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
				wlog("cannot login for account deletion: \(error)")
				// do not escalate the error, as we may not have an account at all
				completion(nil)

			case .success(let sc):
				guard let scc = sc as? ServerChatController else {
					flog("cannot cast ServerChat to ServerChatController")
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

					try? self.removePasswordFromKeychain()
					try? removeSecretFromKeychain(label: ServerChatAccessTokenKeychainKey)
					try? removeSecretFromKeychain(label: ServerChatRefreshTokenKeychainKey)

					self.closeServerChat()

					completion(nil)
				}
			}
		}
	}

	// MARK: - Private

	/// Creates a factory instance.
	private init(peerID: PeerID) {
		self.peerID = peerID
		globalRestClient.completionQueue = Self.dQueue
	}


	// MARK: Static Variables

	/// Singleton instance.
	private static var instance: ServerChatFactory? = nil

	/// DispatchQueue for all actions on a `ServerChatFactory`; uses the `AccountController` queue for efficiency, not for logic dependence.
	private static var dQueue: DispatchQueue { return AccountController.dQueue }

	// MARK: Constants

	/// PeerID of the user.
	private let peerID: PeerID

	/// We need to keep a strong reference to the client s.t. it is not destroyed while requests are in flight
	private let globalRestClient = MXRestClient(homeServer: homeServerURL) { _data in
		flog("matrix certificate rejected: \(String(describing: _data))")
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

	/// Matrix userId based on user's PeerID.
	private var userId: String { return peerID.serverChatUserId }

	// MARK: Methods

	/// Closes the underlying session and invalidates the global ServerChatController instance; must be called on `dQueue`.
	private func closeServerChat(with error: Error? = nil) {
		serverChatController?.close()
		serverChatController = nil

		Self.delegate?.serverChatClosed(error: error)
	}

	/// Login, create account or get readily configured `ServerChatController`.
	private func setup(onlyLogin: Bool = false, _ completion: @escaping (Result<ServerChat, ServerChatError>) -> Void) {
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
				wlog("Could not remove password from keychain after insert failed: \(removeError.localizedDescription)")
			}

			completion(.failure(.fatal(error)))
			return
		}

		let registerParameters: [String: Any] = ["auth" : ["type" : kMXLoginFlowTypeDummy],
												 "username" : username,
												 "password" : passwordRawData.base64EncodedString(),
												 "device_id" : userId]

		globalRestClient.register(parameters: registerParameters) { registerResponse in
			switch registerResponse.toResult() {
			case .failure(let error):
				do {
					try self.removePasswordFromKeychain()
				} catch {
					elog("Could not remove password from keychain after failed registration: \(error.localizedDescription)")
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

				// this cost me at least one week: the credentials have the port stripped, because the `home_server` field in mxLoginResponse does not contain the port …
				credentials.homeServer = homeServerURL.absoluteString

				completion(.success(credentials))
			}
		}

		passwordRawData.resetBytes(in: 0..<passwordRawData.count)
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
											"user" : userId,
											// probably a bad idea for the far future to use the userId as the device_id here, but hell yeah
											"device_id" : userId]) { response in
			if let error = response.error as NSError?,
			   let mxErrCode = error.userInfo[kMXErrorCodeKey] as? String,
			   mxErrCode == "M_INVALID_USERNAME" {
				elog("Our account seems to be deleted. Removing local password to be able to re-register.")
				do {
					try self.removePasswordFromKeychain()
				} catch let pwError {
					wlog("Removing local password failed, not an issue if not existant: \(pwError.localizedDescription)")
				}
			}

			guard let json = response.value else {
				elog("Login response is nil.")
				completion(.failure(.fatal(unexpectedNilError())))
				return
			}
			guard let loginResponse = MXLoginResponse(fromJSON: json) else {
				completion(.failure(.parsing("ERROR: Cannot create login response from JSON \(json).")))
				return
			}

			let credentials = MXCredentials(loginResponse: loginResponse, andDefaultCredentials: self.globalRestClient.credentials)

			try? removeSecretFromKeychain(label: ServerChatAccessTokenKeychainKey)
			try? removeSecretFromKeychain(label: ServerChatRefreshTokenKeychainKey)
			credentials.accessToken.map { try? persistSecretInKeychain(secret: $0, label: ServerChatAccessTokenKeychainKey) }
			credentials.refreshToken.map { try? persistSecretInKeychain(secret: $0, label: ServerChatRefreshTokenKeychainKey) }

			completion(.success(credentials))
		}
	}

	/// Tries to create a new session with a previous access token; prevents from creating new devices in Dendrite.
	private func resumeSession(_ failure: @escaping (ServerChatError) -> Void) {
		do {
			let token = try secretFromKeychain(label: ServerChatAccessTokenKeychainKey)
			let refreshToken = try secretFromKeychain(label: ServerChatRefreshTokenKeychainKey)
			let creds = MXCredentials(homeServer: homeServerURL.absoluteString, userId: userId, accessToken: token)
			creds.refreshToken = refreshToken
			setupInstance(with: creds, failure)
		} catch let error {
			failure(.fatal(error))
		}
	}

	/// Sets the `serverChatController` singleton and starts the server chat session.
	private func setupInstance(with credentials: MXCredentials, _ failure: ((ServerChatError) -> Void)? = nil) {
		let restClient: MXRestClient = MXRestClient(credentials: credentials, unrecognizedCertificateHandler: { data in
			flog("server chat certificate is not trusted.")
			Self.delegate?.serverChatCertificateIsInvalid()
			return false
		}, persistentTokenDataHandler: { callback in
			dlog("server chat persistentTokenDataHandler was called.")
			// Block called when the rest client needs to check the persisted refresh token data is valid and optionally persist new refresh data to disk if it is not.
			callback?([credentials]) { shouldPersist in
				// credentials (access and refresh token) changed during refresh
				guard shouldPersist else { return }

				// The credentials are passed by reference, so their token properties have changed by now.
				credentials.accessToken.map { try? persistSecretInKeychain(secret: $0, label: ServerChatAccessTokenKeychainKey) }
				credentials.refreshToken.map { try? persistSecretInKeychain(secret: $0, label: ServerChatRefreshTokenKeychainKey) }
			}
		}, unauthenticatedHandler: { [weak self] mxError, isSoftLogout, isRefreshTokenAuth, completion in
			// Block called when the rest client has become unauthenticated(E.g. refresh failed or server invalidated an access token).

			guard let strongSelf = self, !strongSelf.isDeletingAccount else { return }

			if let error = mxError {
				flog("server chat session became unauthenticated (soft logout: \(isSoftLogout), refresh token: \(isRefreshTokenAuth)) \(error.errcode ?? "<nil>"): \(error.error ?? "<nil>")")
			} else {
				flog("server chat session became unauthenticated (soft logout: \(isSoftLogout), refresh token: \(isRefreshTokenAuth))")
			}

			Self.dQueue.async {
				strongSelf.closeServerChat(with: mxError?.createNSError())

				completion?()
			}
		})

		restClient.completionQueue = Self.dQueue

		let c = ServerChatController(peerID: peerID, restClient: restClient, dQueue: Self.dQueue)

		c.start { _error in
			Self.dQueue.async {
				if let error = _error {
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
					c.delegate = Self.delegate

					// configure the pusher if server chat account didn't exist when AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken() is called
					Self.remoteNotificationsDeviceToken.map { c.configurePusher(deviceToken: $0) }

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
		try persistInternetPasswordInKeychain(account: userId, url: homeServerURL, password)
	}

	/// Retrieves our account's password from the keychain.
	private func passwordFromKeychain() throws -> String {
		return try internetPasswordFromKeychain(account: userId, url: homeServerURL)
	}

	/// force-delete local account information. Only use as a last resort!
	private func removePasswordFromKeychain() throws {
		try removeInternetPasswordFromKeychain(account: userId, url: homeServerURL)
	}
}
