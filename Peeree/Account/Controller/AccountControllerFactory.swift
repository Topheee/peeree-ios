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
import PeereeServerAPI

// Package Dependencies
import KeychainWrapper

/// Responsible for creating an ``AccountController`` singleton.
public final class AccountControllerFactory {

	// MARK: Classes, Structs, Enums

	/// Names of notifications sent by `AccountControllerFactory`.
	public enum NotificationName: String {
		/// Notifications regarding identity management.
		case accountCreated, accountDeleted
	}

	/// Singleton instance.
	public static let shared = AccountControllerFactory()

	/// Whether the account deletion process is running.
	public private (set) var isDeletingAccount = false

	/// Whether a request to create an account is in flight.
	public var isCreatingAccount: Bool {
		return !creatingInstanceCallbacks.isEmpty
	}

	// MARK: Methods

	/// Call this as soon as possible.
	public func initialize(viewModel: any SocialViewModelDelegate, test: Bool = false) {
		self.dQueue.async {
			self.viewModel = viewModel

			SwaggerClientAPI.host = test ? "localhost:10443" : "rest.peeree.de:39517"
			SwaggerClientAPI.apiResponseQueue.underlyingQueue = self.dQueue
		}
	}

	/// Retrieves the singleton on its `DispatchQueue`; call all methods on `AccountController` only directly from `getter`!
	public func use(_ getter: @escaping (AccountController) -> Void, _ unavailable: ((Error?) -> Void)? = nil) {
		dQueue.async {
			if let i = self.instance {
				getter(i)
			} else if let vm = self.viewModel {
				do {
					if let ac = AccountController.load(keyPair: try KeyPair(fromKeychainWithPrivateTag: Self.PrivateKeyTag, publicTag: Self.PublicKeyTag, algorithm: PeereeIdentity.KeyAlgorithm, size: PeereeIdentity.KeySize), viewModel: vm, dQueue: self.dQueue) {
						self.setInstance(ac)
						getter(ac)
					} else { unavailable?(nil) }
				} catch {
					unavailable?((error as NSError).code == errSecItemNotFound ? nil : error)
				}
			} else {
				unavailable?(createApplicationError(localizedDescription: "AccountControllerFactory is uninitialized!"))
			}
		}
	}

	/// Creates a new `PeereeIdentity` for the user.
	public func createAccount(email: String? = nil, _ completion: @escaping (Result<AccountController, Error>) -> Void) {
		dQueue.async { [self] in
			if let i = instance {
				completion(.success(i))
				return
			}

			guard let vm = self.viewModel else {
				completion(.failure(createApplicationError(localizedDescription: "AccountControllerFactory is uninitialized!")))
				return
			}

			creatingInstanceCallbacks.append(completion)
			guard creatingInstanceCallbacks.count == 1 else { return }

			DispatchQueue.main.async {
				vm.accountExists = .turningOn
			}

			// generate our asymmetric key pair
			let keyPair: KeyPair
			do {
				// try to remove the old key, just to be sure
				try? KeychainWrapper.removePublicKeyFromKeychain(tag: Self.PublicKeyTag, algorithm: .ec, size: PeereeIdentity.KeySize)
				try? KeychainWrapper.removePrivateKeyFromKeychain(tag: Self.PrivateKeyTag, algorithm: .ec, size: PeereeIdentity.KeySize)

				// this will add the pair to the keychain, from where it is read later by the constructor
				keyPair = try KeyPair(privateTag: Self.PrivateKeyTag, publicTag: Self.PublicKeyTag, algorithm: PeereeIdentity.KeyAlgorithm, size: PeereeIdentity.KeySize, persistent: true)

				SwaggerClientAPI.dataSource = InitialSecurityDataSource(keyPair: keyPair)
			} catch let error {
				reportCreatingInstance(result: .failure(error), vm: vm)
				return
			}

			AccountAPI.putAccount(email: email) { (account, error) in
				guard let account else {
					let desc = NSLocalizedString("Server did provide malformed or no account information", comment: "Error when an account creation request response is malformed")
					self.reportCreatingInstance(result: .failure(error ?? NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : desc])), vm: vm)
					return
				}

				let a = AccountController.create(account: account, keyPair: keyPair, viewModel: vm, dQueue: self.dQueue)
				self.setInstance(a)
				self.reportCreatingInstance(result: .success(a), vm: vm)

				NotificationName.accountCreated.postAsNotification(object: a, userInfo: [PeerID.NotificationInfoKey : account.peerID])
			}
		}
	}

	/// Permanently delete this identity; do not use this `AccountController` instance after this completes successfully!
	public func deleteAccount(_ completion: @escaping (Error?) -> Void) {
		guard !isDeletingAccount, let ac = instance else { return }
		isDeletingAccount = true

		if let vm = self.viewModel {
			DispatchQueue.main.async {
				vm.accountExists = .turningOff
			}
		}

		AccountAPI.deleteAccount { (_, error) in
			var reportedError = error
			if let error {
				switch error {
				case .httpError(403, let messageData):
					elog(Self.LogTag, "Our account seems to not exist on the server. Will silently delete local references. Body: \(String(describing: messageData))")
					reportedError = nil
				default:
					break
				}
			}

			if reportedError == nil {
				ac.clearLocalData() {
					self.instance = nil
					self.isDeletingAccount = false

					completion(reportedError)

					NotificationName.accountDeleted.postAsNotification(object: self)
				}
			} else {
				self.isDeletingAccount = false
				completion(reportedError)
			}

			if let vm = self.viewModel {
			 DispatchQueue.main.async {
				 vm.userPeerID = nil
				 vm.accountExists = reportedError == nil ? .off : .on
			 }
		 }
		}
	}

	// MARK: Private

	/// For singleton pattern.
	private init() {}

	// MARK: Classes, Structs, Enums

	/// Used during account creation.
	private struct InitialSecurityDataSource: SecurityDataSource {
		// MARK: Constants

		let keyPair: KeyPair

		// MARK: SecurityDataSource

		public func getPeerID() -> String {
			return ""
		}

		public func getSignature() -> String {
			do {
				return try keyPair.externalPublicKey().base64EncodedString()
			} catch let error {
				flog(AccountControllerFactory.LogTag, "exporting public key failed: \(error)")
				return ""
			}
		}
	}

	// MARK: Static Constants

	// Log tag.
	private static let LogTag = "Account"

	/// Keychain property.
	private static let PrivateKeyTag = "com.peeree.keys.restkey.private".data(using: .utf8)!

	/// Keychain property.
	private static let PublicKeyTag = "com.peeree.keys.restkey.public".data(using: .utf8)!

	/// The dispatch queue for actions on `AccountController`; should be private but is used in Server Chat as well for efficiency.
	private let dQueue = DispatchQueue(label: "de.peeree.AccountController", qos: .default)

	/// Singleton instance of this class.
	private var instance: AccountController?

	/// Collected callbacks which where requesting a new account (through `createAcction()`)
	private var creatingInstanceCallbacks = [(Result<AccountController, Error>) -> Void]()

	private var viewModel: (any SocialViewModelDelegate)?

	// MARK: Static Functions

	/// Establish the singleton instance.
	private func setInstance(_ ac: AccountController) {
		instance = ac
		SwaggerClientAPI.dataSource = ac
	}

	/// Concludes registration process; must be called on `dQueue`!
	private func reportCreatingInstance(result: Result<AccountController, Error>, vm: any SocialViewModelDelegate) {
		DispatchQueue.main.async {
			switch result {
			case .success(_):
				vm.accountExists = .on
			case .failure(_):
				vm.accountExists = .off
			}
		}

		creatingInstanceCallbacks.forEach { $0(result) }
		creatingInstanceCallbacks.removeAll()
	}
}
