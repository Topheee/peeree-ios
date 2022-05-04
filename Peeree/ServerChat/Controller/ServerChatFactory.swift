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
		use { factory in
			factory?.serverChatController?.close()
			factory?.serverChatController = nil
		}
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

				scc.deleteAccount(password: password) { error in
					if let error = error {
						completion(error)
						return
					}

					do {
						try self.removePasswordFromKeychain()
						try removeSecretFromKeychain(label: ServerChatAccessTokenKeychainKey)
						try removeSecretFromKeychain(label: ServerChatRefreshTokenKeychainKey)
					} catch let error {
						elog("\(error.localizedDescription)")
					}

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

	/// Matrix userId based on user's PeerID.
	private var userId: String { return serverChatUserId(for: peerID) }

	// MARK: Methods

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
				case .identityMissing:
					// this is expected, e.g. when creating the account
					break
				case .parsing(let parsingMessage):
					wlog("Parsing during server chat login failed: \(parsingMessage)")
				case .sdk(let sdkError):
					wlog("Something in the SDK during server chat login failed: \(sdkError.localizedDescription)")
				case .fatal(let fatalError):
					wlog("Something really bad in the SDK during server chat login failed: \(fatalError.localizedDescription)")
				}

				self.createAccount { createAccountResult in
					switch createAccountResult {
					case .success(let credentials):
						self.setupInstance(with: credentials)
					case .failure(let error):
						self.reportCreatingInstance(result: .failure(error))
					}
				}
			}
		}
	}

	/// Creates an account on the chat server.
	private func createAccount(_ completion: @escaping (Result<MXCredentials, ServerChatError>) -> Void) {
		let username = serverChatUserName(for: peerID)

		var passwordRawData: Data
		do {
			passwordRawData = try generateRandomData(length: Int.random(in: 24...26))
		} catch let error {
			completion(.failure(.sdk(error)))
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

			completion(.failure(.sdk(error)))
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
		} catch let error {
			completion(.failure(.fatal(error)))
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

	// as this method also invalidates the deviceId, other users cannot send us encrypted messages anymore. So we never logout except for when we delete the account.
	/// this will close the underlying session. Do not re-use it (do not make any more calls to this ServerChatController instance).
	private func logout(completion: @escaping (Error?) -> Void) {
		// if this fails we cannot do anything anyway
		self.serverChatController?.logout(completion)
		// we need to drop the instance s.t. no two logout requests are made on the same instance
		self.serverChatController = nil
	}

	/// Sets the `serverChatController` singleton and starts the server chat session.
	private func setupInstance(with credentials: MXCredentials, _ failure: ((ServerChatError) -> Void)? = nil) {
		let c = ServerChatController(peerID: peerID, credentials: credentials, dQueue: Self.dQueue) {
			// I hope the credentials are passed by reference …
			credentials.accessToken.map { try? persistSecretInKeychain(secret: $0, label: ServerChatAccessTokenKeychainKey) }
			credentials.refreshToken.map { try? persistSecretInKeychain(secret: $0, label: ServerChatRefreshTokenKeychainKey) }
		}

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

	private func passwordFromKeychain() throws -> String {
		try internetPasswordFromKeychain(account: userId, url: homeServerURL)
	}

	/// force-delete local account information. Only use as a last resort!
	private func removePasswordFromKeychain() throws {
		try removeInternetPasswordFromKeychain(account: userId, url: homeServerURL)
	}
}
