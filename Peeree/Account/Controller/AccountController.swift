//
//  AccountController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.05.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation
import ImageIO
import CoreServices

/// Informant of failures in the `AccountController`.
public protocol AccountControllerDelegate {
	/// The request to pin `peerID` failed with `error`.
	func pin(of peerID: PeerID, failedWith error: Error)

	/// A requested action on `peerID` failed due to the server assuming a different public key than us; this may imply an attack on the user.
	func publicKeyMismatch(of peerID: PeerID)

	/// The fallback process for `unauthorized` errors failed.
	func sequenceNumberResetFailed(error: ErrorResponse)
}

/**
 * Central singleton managing all communication with the Peeree servers.
 * Do NOT use the network calls in DefaultAPI directly, as then the sequence number won't be updated appropriately
 */
public class AccountController: SecurityDataSource {

	// MARK: Classes, Structs, Enums

	/// Names of notifications sent by `AccountController`.
	public enum NotificationName: String {
		/// Notifications regarding pins.
		case pinFailed, unpinFailed, pinMatch, unmatch, unpinned

		/// Notifications regarding identity management.
		case accountCreated, accountDeleted

		/// Notification when a picture was reported as inappropriate.
		case peerReported
	}

	// MARK: Static Variables

	/// Informed party when `AccountController` actions fail.
	public static var delegate: AccountControllerDelegate?

	/// Call from `dQueue` only!
	static var isCreatingAccount: Bool {
		return !creatingInstanceCallbacks.isEmpty
	}

	// MARK: Static Functions

	/// Retrieves the singleton on its `DispatchQueue`; call all methods on `AccountController` only directly from `getter`!
	public static func use(_ getter: @escaping (AccountController) -> Void, _ unavailable: (() -> Void)? = nil) {
		dQueue.async {
			if let i = instance {
				getter(i)
			} else if let ac = load() {
				instance = ac
				getter(ac)
			} else { unavailable?() }
		}
	}

	/// Creates a new `PeereeIdentity` for the user.
	public static func createAccount(email: String? = nil, _ completion: @escaping (Result<AccountController, Error>) -> Void) { dQueue.async {
		if let i = instance {
			completion(.success(i))
			return
		}

		creatingInstanceCallbacks.append(completion)
		guard creatingInstanceCallbacks.count == 1 else { return }

		// generate our asymmetric key pair
		let keyPair: KeyPair
		do {
			// try to remove the old key, just to be sure
			try? removeFromKeychain(tag: AccountController.PublicKeyTag, keyType: PeereeIdentity.KeyType, keyClass: kSecAttrKeyClassPublic, size: PeereeIdentity.KeySize)
			try? removeFromKeychain(tag: AccountController.PrivateKeyTag, keyType: PeereeIdentity.KeyType, keyClass: kSecAttrKeyClassPrivate, size: PeereeIdentity.KeySize)

			// this will add the pair to the keychain, from where it is read later by the constructor
			keyPair = try KeyPair(label: AccountController.KeyLabel, privateTag: AccountController.PrivateKeyTag, publicTag: AccountController.PublicKeyTag, type: PeereeIdentity.KeyType, size: PeereeIdentity.KeySize, persistent: true)

			SwaggerClientAPI.dataSource = InitialSecurityDataSource(keyPair: keyPair)
		} catch let error {
			reportCreatingInstance(result: .failure(error))
			return
		}

		AccountAPI.putAccount(email: email) { (_account, _error) in
			guard let account = _account else {
				let desc = NSLocalizedString("Server did provide malformed or no account information", comment: "Error when an account creation request response is malformed")
				reportCreatingInstance(result: .failure(_error ?? NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : desc])))
				return
			}

			UserDefaults.standard.set(account.peerID.uuidString, forKey: PeerIDKey)
			UserDefaults.standard.set(NSNumber(value: account.sequenceNumber), forKey: SequenceNumberKey)

			let a = AccountController(peerID: account.peerID, sequenceNumber: account.sequenceNumber, keyPair: keyPair)
			instance = a
			reportCreatingInstance(result: .success(a))

			NotificationName.accountCreated.postAsNotification(object: a, userInfo: [PeerID.NotificationInfoKey : account.peerID])
		}
	} }

	// MARK: Variables

	/// The crown juwels of the user and the second part of the user's identity.
	let keyPair: KeyPair

	/// The identifier of the user on our social network.
	let peerID: PeerID

	/// The user's unique identity on our social network.
	var identity: PeereeIdentity { return PeereeIdentity(peerID: peerID, publicKey: keyPair.publicKey) }

	/// The email address associated with this account; if any.
	private (set) var accountEmail: String? {
		didSet {
			if accountEmail != nil && accountEmail! != "" {
				UserDefaults.standard.set(accountEmail, forKey: AccountController.EmailKey)
			} else {
				UserDefaults.standard.removeObject(forKey: AccountController.EmailKey)
			}
		}
	}

	/// Whether the account deletion process is running.
	private (set) var isDeletingAccount = false

	/// Retrieves the full known public key of `peerID`, if available.
	public func publicKey(of peerID: PeerID) -> Data? { return pinnedPeers[peerID] }

	/// Retrieves the full known identity of `peerID`.
	public func id(of peerID: PeerID) throws -> PeereeIdentity {
		guard let publicKeyData = pinnedPeers[peerID] else {
			throw createApplicationError(localizedDescription: NSLocalizedString("Unknown peer.", comment: "Requested information about an unknown peer."))
		}

		return PeereeIdentity(peerID: peerID, publicKey: try AsymmetricPublicKey(from: publicKeyData, type: PeereeIdentity.KeyType, size: PeereeIdentity.KeySize))
	}

	/// Returns whether we have a pin match with that specific PeerID. Note, that this does NOT imply we have a match with a concrete PeerInfo of that PeerID, as that PeerInfo may be a malicious peer
	public func hasPinMatch(_ peerID: PeerID) -> Bool {
		// it is enough to check whether we are pinned by peerID, as we only know that if we matched
		return pinnedByPeers.contains(peerID)
	}

	/// Returns whether we pinned that specific PeerIdentity.
	public func isPinned(_ id: PeereeIdentity) -> Bool {
		return pinnedPeers[id.peerID] == id.publicKeyData
	}

	/// Checks whether the pinning process is (already) running for `peerID`.
	public func isPinning(_ peerID: PeerID) -> Bool {
		return pinningPeers.contains(peerID)
	}

	/// Pins a person and checks for a pin match.
	public func pin(_ id: PeereeIdentity) {
		let peerID = id.peerID
		guard !isPinned(id) && !isPinning(peerID) else { return }

		pinningPeers.insert(peerID)
		updateModels(of: [id])

		PinsAPI.putPin(pinnedID: peerID, pinnedKey: id.publicKeyData.base64EncodedData()) { (_isPinMatch, _error) in
			self.pinningPeers.remove(peerID)

			if let error = _error {
				self.preprocessAuthenticatedRequestError(error)
				// possible HTTP errors:
				// 409: non-matching public key
				//
				switch error {
				case .httpError(409, _), .sessionTaskError(409?, _, _):
					Self.delegate?.publicKeyMismatch(of: peerID)
				default:
					Self.delegate?.pin(of: peerID, failedWith: error)
				}
				self.post(.pinFailed, peerID)
			} else if let isPinMatch = _isPinMatch {
				self.pin(id: id, isPinMatch: isPinMatch)
			} else {
				self.post(.pinFailed, peerID)
			}

			self.updateModels(of: [id])
		}
	}

	/// Removes the pin from a person.
	public func unpin(id: PeereeIdentity) {
		guard isPinned(id) else { return }
		let peerID = id.peerID

		unpinningPeers.insert(peerID)
		updateModels(of: [id])

		PinsAPI.deletePin(pinnedID: peerID) { (_, _error) in
			self.unpinningPeers.remove(peerID)

			if let error = _error {
				self.preprocessAuthenticatedRequestError(error)
				self.post(.unpinFailed, peerID)
			} else {
				self.removePin(from: id)
			}

			self.updateModels(of: [id])
		}
	}

	/// Reports the picture of a person as inappropriate.
	public func report(model: PeerViewModel, _ errorCallback: @escaping (Error) -> Void) {
		guard let portrait = model.cgPicture, let hash = model.pictureHash else { return }
		
		let hashString = hash.hexString()
		let jpgData: Data

		do {
			#if os(iOS)
			if let data = model.picture?.jpegData(compressionQuality: AccountController.UploadCompressionQuality) {
				jpgData = data
				let str = jpgData[jpgData.startIndex...jpgData.startIndex.advanced(by: 20)].hexString()
				ilog("sending \(str)")
			} else {
				jpgData = try portrait.jpgData(compressionQuality: AccountController.UploadCompressionQuality)
			}
			#else
			jpgData = try portrait.jpgData(compressionQuality: AccountController.UploadCompressionQuality)
			#endif
		} catch let error {
			errorCallback(error)
			return
		}
		
		ContentfilterAPI.putContentFilterPortraitReport(body: jpgData as Data, reportedPeerID: model.peerID, hash: hashString) { (_, _error) in
			if let error = _error {
				self.preprocessAuthenticatedRequestError(error)
				errorCallback(error)
			} else {
				DispatchQueue.main.async {
					PeereeIdentityViewModelController.pendingObjectionableImageHashes[hash] = Date()

					let save = PeereeIdentityViewModelController.pendingObjectionableImageHashes
					Self.dQueue.async {
						archiveObjectInUserDefs(save as NSDictionary, forKey: AccountController.PendingObjectionableImageHashesKey)
					}

					self.post(.peerReported, model.peerID)
				}
			}
		}
	}

	/// Downloads objectionable content hashes.
	public func refreshBlockedContent(_ errorCallback: @escaping (Error) -> Void) {
		guard self.lastObjectionableContentRefresh.addingTimeInterval(AccountController.ObjectionableContentRefreshThreshold) < Date() else { return }

		ContentfilterAPI.getContentFilterPortraitHashes(startDate: self.lastObjectionableContentRefresh) { (_hexHashes, _error) in
			if let error = _error {
				self.preprocessAuthenticatedRequestError(error)
				errorCallback(error)
			} else if let hexHashes = _hexHashes {
				let hashesAsData = Set<Data>(hexHashes.compactMap { Data(hexString: $0) })

				let nsPendingObjectionableImageHashes: NSDictionary? = unarchiveObjectFromUserDefs(AccountController.PendingObjectionableImageHashesKey)
				let pendingObjectionableImageHashes = (nsPendingObjectionableImageHashes as? Dictionary<Data,Date> ?? Dictionary<Data,Date>()).filter { element in
					return !hashesAsData.contains(element.key)
				}

				archiveObjectInUserDefs(hashesAsData as NSSet, forKey: AccountController.ObjectionableImageHashesKey)
				archiveObjectInUserDefs(pendingObjectionableImageHashes as NSDictionary, forKey: AccountController.PendingObjectionableImageHashesKey)

				self.lastObjectionableContentRefresh = Date()
				UserDefaults.standard.set(self.lastObjectionableContentRefresh.timeIntervalSinceReferenceDate, forKey: AccountController.ObjectionableContentRefreshKey)

				DispatchQueue.main.async {
					PeereeIdentityViewModelController.objectionableImageHashes = hashesAsData
					PeereeIdentityViewModelController.pendingObjectionableImageHashes = pendingObjectionableImageHashes
				}
			} else {
				errorCallback(ErrorResponse.parseError(nil))
			}
		}
	}

	/// Persists the pin.
	private func pin(id: PeereeIdentity, isPinMatch: Bool) {
		let peerID = id.peerID

		if pinnedPeers[peerID] != id.publicKeyData {
			pinnedPeers[peerID] = id.publicKeyData
			archiveObjectInUserDefs(pinnedPeers as NSDictionary, forKey: AccountController.PinnedPeersKey)
		}

		// check whether the pin match state changed
		guard pinnedByPeers.contains(peerID) != isPinMatch else { return }

		if isPinMatch {
			// this is a pin match we weren't aware of
			pinnedByPeers.insert(peerID)

			// post this on the main queue
			self.post(.pinMatch, peerID)
		} else {
			// the opposite removed the pin (unmatched us)
			pinnedByPeers.remove(peerID)

			// post this on the main queue
			self.post(.unmatch, peerID)
		}

		archiveObjectInUserDefs(pinnedByPeers as NSSet, forKey: AccountController.PinnedByPeersKey)
	}

	/// Persists the pin removal.
	private func removePin(from id: PeereeIdentity) {
		let peerID = id.peerID

		pinnedPeers.removeValue(forKey: peerID)
		archiveObjectInUserDefs(pinnedPeers as NSDictionary, forKey: AccountController.PinnedPeersKey)

		if pinnedByPeers.remove(peerID) != nil {
			archiveObjectInUserDefs(pinnedByPeers as NSSet, forKey: AccountController.PinnedByPeersKey)
		}

		post(.unpinned, peerID)
	}

	/// Retrieve the pin (matched) status from the server. If `force` is `false`, do not update if we believe we have a pin match.
	public func updatePinStatus(of id: PeereeIdentity, force: Bool, _ completion: ((PinState) -> Void)? = nil) {
		// attack scenario: Eve sends pin match indication to Alice, but Alice only asks server, if she pinned Eve in the first place => Eve can observe Alice's internet communication and can figure out, whether Alice pinned her, depending on whether Alice' asked the server after the indication.
		// thus, we (Alice) have to at least once validate with the server, even if we know, that we did not pin Eve
		// This is achieved through the hasPinMatch query, as this will always fail, if we do not have a true match, thus we query ALWAYS the server when we receive a pin match indication. If flooding attack (Eve sends us dozens of indications) gets serious, implement above behaviour, that we only validate once

		guard force || !hasPinMatch(id.peerID) else {
			completion?(.pinMatch)
			return
		}

		let pinPublicKey = id.publicKeyData.base64EncodedData()

		PinsAPI.getPin(pinnedID: id.peerID, pinnedKey: pinPublicKey) { (_pinStatus, _error) in
			guard _error == nil else {
				self.preprocessAuthenticatedRequestError(_error!)
				return
			}

			if let pinStatus = _pinStatus {
				switch pinStatus {
				case 0:
					self.pin(id: id, isPinMatch: false)
				case 1:
					self.pin(id: id, isPinMatch: true)
				default:
					self.removePin(from: id)
				}

				self.updateModels(of: [id])

				completion?(self.pinState(of: id.peerID))
			}
		}
	}

	/// Permanently delete this identity; do not use this `AccountController` instance after this completes successfully!
	public func deleteAccount(_ completion: @escaping (Error?) -> Void) {
		guard !isDeletingAccount else { return }
		isDeletingAccount = true
		let oldPeerID = peerID

		AccountAPI.deleteAccount { (_, _error) in
			var reportedError = _error
			if let error = _error {
				switch error {
				case .httpError(403, let messageData):
					elog("Our account seems to not exist on the server. Will silently delete local references. Body: \(String(describing: messageData))")
					reportedError = nil
				default:
					self.preprocessAuthenticatedRequestError(error)
				}
			}
			if reportedError == nil {
				self.clearLocalData(oldPeerID: oldPeerID) {
					self.isDeletingAccount = false
					completion(reportedError)
					NotificationName.accountDeleted.postAsNotification(object: self)
				}
			} else {
				self.isDeletingAccount = false
				completion(reportedError)
			}
		}
	}

	/// Changes the email address of the account or removes it if `email` is the empty string.
	public func update(email: String, _ completion: @escaping (Error?) -> Void) {
		guard email != "" else { deleteEmail(completion); return }
		AccountAPI.putAccountEmail(email: email) { (_, _error) in
			if let error = _error {
				self.preprocessAuthenticatedRequestError(error)
			} else {
				self.accountEmail = email
			}
			completion(_error)
		}
	}

	/// Removes the email address from the account.
	public func deleteEmail(_ completion: @escaping (Error?) -> Void) {
		AccountAPI.deleteAccountEmail { (_, _error) in
			if let error = _error {
				self.preprocessAuthenticatedRequestError(error)
			} else {
				self.accountEmail = nil
			}
			completion(_error)
		}
	}
	
	// MARK: SecurityDataSource

	/// Returns the string representation of our UUID.
	public func getPeerID() -> String {
		return peerID.uuidString
	}

	/// Authenticates the server request.
	public func getSignature() -> String {
		do {
			return try computeSignature()
		} catch let error {
			flog("Cannot compute signature: \(error)")
			return ""
		}
	}

	// MARK: - Private

	/// Creates the AccountController singleton and installs it in the rest of the app.
	private init(peerID: PeerID, sequenceNumber: Int32, keyPair: KeyPair) {
		self.peerID = peerID
		self.sequenceNumber = sequenceNumber

		self.keyPair = keyPair
		let nsPinnedBy: NSSet? = unarchiveObjectFromUserDefs(AccountController.PinnedByPeersKey)
		pinnedByPeers = nsPinnedBy as? Set<PeerID> ?? Set()
		let nsPinned: NSDictionary? = unarchiveObjectFromUserDefs(AccountController.PinnedPeersKey)
		pinnedPeers = nsPinned as? [PeerID : Data] ?? [PeerID : Data]()
		lastObjectionableContentRefresh = Date(timeIntervalSinceReferenceDate: UserDefaults.standard.double(forKey: AccountController.ObjectionableContentRefreshKey))
		accountEmail = UserDefaults.standard.string(forKey: AccountController.EmailKey)

		opQueue.underlyingQueue = Self.dQueue

		// side-effects (not the best style …)
		SwaggerClientAPI.apiResponseQueue = opQueue
		SwaggerClientAPI.dataSource = self

		let models: [PeereeIdentityViewModel] = pinnedPeers.compactMap { (peerID, publicKeyData) in
			guard let id = PeereeIdentity(peerID: peerID, publicKeyData: publicKeyData) else { return nil }
			return PeereeIdentityViewModel(id: id, pinState: self.pinState(of: peerID))
		}

		DispatchQueue.main.async {
			PeereeIdentityViewModelController.userPeerID = peerID
			for model in models {
				PeereeIdentityViewModelController.insert(model: model)
			}
		}
	}

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
				flog("exporting public key failed: \(error)")
				return ""
			}
		}
	}

	// MARK: Static Constants

	/// User defaults key for pinned peers dictionary
	private static let PinnedPeersKey = "PinnedPeers"
	/// User defaults key for pinned by peers dictionary
	private static let PinnedByPeersKey = "PinnedByPeers"
	/// User defaults key for user's email
	private static let EmailKey = "Email"
	/// User defaults key for sequence number
	private static let SequenceNumberKey = "SequenceNumber"
	/// User defaults key for objectionable image hashes
	private static let ObjectionableImageHashesKey = "ObjectionableImageHashes"
	/// User defaults key for reported and not yet objectionable image hashes
	private static let PendingObjectionableImageHashesKey = "PendingObjectionableImageHashesKey"
	/// User defaults key for objectionable content refresh timestamp
	private static let ObjectionableContentRefreshKey = "ObjectionableContentRefresh"
	/// JPEG compression quality for portrait report uploads.
	private static let UploadCompressionQuality: CGFloat = 0.3

	/// Keychain property.
	private static let PrivateKeyTag = "com.peeree.keys.restkey.private".data(using: .utf8)!
	/// Keychain property.
	private static let PublicKeyTag = "com.peeree.keys.restkey.public".data(using: .utf8)!
	/// Keychain property.
	private static let KeyLabel = "Peeree Identity"

	/// Key to our identity in UserDefaults
	private static let PeerIDKey = "PeerIDKey"

	/// Refresh objectionable content every day at most (or when the app is killed).
	private static let ObjectionableContentRefreshThreshold: TimeInterval = 60 * 60 * 24

	/// The number added to the current sequence number after each server chat operation.
	private static let SequenceNumberIncrement: Int32 = 13

	/// The dispatch queue for actions on `AccountController`; should be private but is used in Server Chat as well for efficiency.
	/*private*/ static let dQueue = DispatchQueue(label: "de.peeree.AccountController", qos: .default)

	/// Singleton instance of this class.
	private static var instance: AccountController?

	/// Collected callbacks which where requesting a new account (through `createAcction()`)
	private static var creatingInstanceCallbacks = [(Result<AccountController, Error>) -> Void]()

	// MARK: Static Functions

	/// Factory method for `AccountController`.
	private static func load() -> AccountController? {
		guard let str = UserDefaults.standard.string(forKey: Self.PeerIDKey) else { return nil }
		guard let peerID = UUID(uuidString: str) else {
			wlog("our peer ID is not a UUID, deleting!")
			UserDefaults.standard.removeObject(forKey: Self.PeerIDKey)
			return nil
		}

		// TODO move sequence number into keychain
		let sequenceNumber: Int32
		if let sn = (UserDefaults.standard.object(forKey: Self.SequenceNumberKey) as? NSNumber)?.int32Value {
			sequenceNumber = sn
		} else {
			wlog("Sequence Number is nil")
			// we set it to 0 s. t. it can be reset later by our normal reset process
			sequenceNumber = 0
		}

		do {
			let ac = AccountController(peerID: peerID, sequenceNumber: sequenceNumber, keyPair: try KeyPair(fromKeychainWith: AccountController.KeyLabel, privateTag: AccountController.PrivateKeyTag, publicTag: AccountController.PublicKeyTag, type: PeereeIdentity.KeyType, size: PeereeIdentity.KeySize))

			return ac
		} catch let error {
			flog("cannot load our key from keychain: \(error)")
			return nil
		}
	}

	/// Concludes registration process; must be called on `dQueue`!
	static private func reportCreatingInstance(result: Result<AccountController, Error>) {
		creatingInstanceCallbacks.forEach { $0(result) }
		creatingInstanceCallbacks.removeAll()
	}

	// MARK: Constants

	/// Operation queue for work on this object.
	private let opQueue = OperationQueue()

	// MARK: Variables

	/*
	 store pinned public key along with peerID as
	 1. Alice pins Bob
	 2. Eve advertises Bob's peerID with her public key
	 3. Alice validates Bob's peerID with Eve's public key and thinks she met Bob again
	 4. Eve convinced Alice successfully that she is Bob
	*/

	/// Pinned peers and their public keys.
	private var pinnedPeers: [PeerID : Data]
	/// Pin matched peers.
	private var pinnedByPeers: Set<PeerID>

	/// Peers with underway requests to pin.
	private var pinningPeers = Set<PeerID>()

	/// Peers with underway requests to unpin from.
	private var unpinningPeers = Set<PeerID>()

	/// Timestamp of last successful refresh of objectionable content.
	private var lastObjectionableContentRefresh: Date

	/// Incrementing secret number we use to authenticate requests to the server.
	private var sequenceNumber: Int32 {
		didSet {
			UserDefaults.standard.set(NSNumber(value: sequenceNumber), forKey: Self.SequenceNumberKey)
		}
	}

	// MARK: Methods

	/// Calculates the current pin state machine state for `peerID`.
	private func pinState(of peerID: PeerID) -> PinState {
		if pinningPeers.contains(peerID) {
			return .pinning
		} else if unpinningPeers.contains(peerID) {
			return .unpinning
		} else if pinnedByPeers.contains(peerID) {
			return .pinMatch
		} else if pinnedPeers[peerID] != nil {
			return .pinned
		} else {
			return .unpinned
		}
	}

	/// Populate changes in `ids` to the appropriate view models.
	private func updateModels(of ids: [PeereeIdentity]) {
		let models = ids.map { id in
			PeereeIdentityViewModel(id: id, pinState: pinState(of: id.peerID))
		}

		DispatchQueue.main.async {
			for model in models {
				PeereeIdentityViewModelController.upsert(peerID: model.peerID, insert: model) { mdl in
					mdl.pinState = model.pinState
				}
			}
		}
	}

	/// Request a new sequence number, since we may have run out of sync with the server.
	private func resetSequenceNumber() {
		wlog("resetting sequence number")
		AuthenticationAPI.deleteAccountSecuritySequenceNumber { (_sequenceNumberDataCipher, _error) in
			guard let sequenceNumberDataCipher = _sequenceNumberDataCipher else {
				if let error = _error {
					elog("resetting sequence number failed: \(error.localizedDescription)")
					Self.delegate?.sequenceNumberResetFailed(error: error)
				}
				return
			}

			self.sequenceNumber = sequenceNumberDataCipher
		}
	}

	/// resets sequence number to state before request if the request did not reach the server
	private func preprocessAuthenticatedRequestError(_ errorResponse: ErrorResponse) {
		switch errorResponse {
		case .httpError(403, let messageData):
			elog("Unauthorized: \(messageData.map { String(data: $0, encoding: .utf8) ?? "(decode failed) code 403." } ?? "code 403.")")
			self.resetSequenceNumber()
		case .parseError(_):
			elog("Response could not be parsed.")
			break
		case .sessionTaskError(let statusCode, _, let error):
			elog("Network error \(statusCode ?? -1) occurred: \(error.localizedDescription)")
			if (error as NSError).domain == NSURLErrorDomain {
				// we did not even reach the server, so we have to decrement our sequenceNumber again
				sequenceNumber = sequenceNumber.subtractingReportingOverflow(AccountController.SequenceNumberIncrement).partialValue
			}
			if statusCode == 403 { // forbidden
				// the signature was invalid, so request a new sequenceNumber
				self.resetSequenceNumber()
			}
		default:
			break
		}
	}

	/// Computes a digital signature based on the current `sequenceNumber` and increments the `sequenceNumber` afterwards.
	private func computeSignature() throws -> String {
		guard let sequenceNumberData = String(sequenceNumber).data(using: .utf8) else {
			throw NSError(domain: "Peeree", code: -2, userInfo: nil)
		}

		sequenceNumber = sequenceNumber.addingReportingOverflow(AccountController.SequenceNumberIncrement).partialValue
		return try keyPair.sign(message: sequenceNumberData).base64EncodedString()
	}

	/// Wipes all data after the account was deleted.
	private func clearLocalData(oldPeerID: PeerID, _ completion: @escaping () -> Void) {
		Self.instance = nil

		self.accountEmail = nil
		UserDefaults.standard.removeObject(forKey: Self.PeerIDKey)
		UserDefaults.standard.removeObject(forKey: Self.EmailKey)
		UserDefaults.standard.removeObject(forKey: Self.SequenceNumberKey)

		pinningPeers.removeAll()
		unpinningPeers.removeAll()

		pinnedPeers.removeAll()
		archiveObjectInUserDefs(pinnedPeers as NSDictionary, forKey: AccountController.PinnedPeersKey)

		pinnedByPeers.removeAll()
		archiveObjectInUserDefs(pinnedByPeers as NSSet, forKey: AccountController.PinnedByPeersKey)

		do {
			try removeFromKeychain(tag: AccountController.PublicKeyTag, keyType: PeereeIdentity.KeyType, keyClass: kSecAttrKeyClassPublic, size: PeereeIdentity.KeySize)
			try removeFromKeychain(tag: AccountController.PrivateKeyTag, keyType: PeereeIdentity.KeyType, keyClass: kSecAttrKeyClassPrivate, size: PeereeIdentity.KeySize)
		} catch let error {
			flog("Could not delete keychain items. Creation of new identity will probably fail. Error: \(error.localizedDescription)")
		}

		SwaggerClientAPI.apiResponseQueue = nil
		SwaggerClientAPI.dataSource = nil
		DispatchQueue.main.async {
			PeereeIdentityViewModelController.clear()
			Self.dQueue.async { completion() }
		}
	}

	/// Sends `notification` with regards to `peerID`.
	private func post(_ notification: NotificationName, _ peerID: PeerID) {
		notification.postAsNotification(object: self, userInfo: [PeerID.NotificationInfoKey : peerID])
	}
}

extension AccountController {
	/// Retrieve the pin (matched) status from the server. If `force` is `false`, do not update if we believe we have a pin match.
	public func updatePinStatus(of peerID: PeerID, force: Bool, _ completion: ((PinState) -> Void)? = nil) {
		do {
			updatePinStatus(of: try self.id(of: peerID), force: force, completion)
		} catch let error {
			elog("Unknown PeerID \(peerID) in updatePinStatus(): \(error)")
		}
	}
}
