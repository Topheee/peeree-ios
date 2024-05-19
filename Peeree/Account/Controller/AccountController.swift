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
import KeychainWrapper
import PeereeCore
import PeereeServerAPI

/// Informant of failures in the `AccountController`.
public protocol AccountControllerDelegate {
	/// The request to pin `peerID` failed with `error`.
	func pin(of peerID: PeereeCore.PeerID, failedWith error: Error)

	/// A requested action on `peerID` failed due to the server assuming a different public key than us; this may imply an attack on the user.
	func publicKeyMismatch(of peerID: PeereeCore.PeerID)

	/// The fallback process for `unauthorized` errors failed.
	func sequenceNumberResetFailed(error: Error)

	/// When this occurs, the last request was not processed correctly.
	func sequenceNumberReset()
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

		/// Notification when a picture was reported as inappropriate.
		case peerReported
	}

	/// Creates a new `AccountController` for the user.
	internal static func create(email: String? = nil, account: Account, keyPair: KeyPair, viewModel: any SocialViewModelDelegate, dQueue: DispatchQueue) -> AccountController {
		UserDefaults.standard.set(account.peerID.uuidString, forKey: Self.PeerIDKey)
		UserDefaults.standard.set(NSNumber(value: account.sequenceNumber), forKey: Self.SequenceNumberKey)

		return AccountController(peerID: account.peerID, sequenceNumber: account.sequenceNumber, keyPair: keyPair, viewModel: viewModel, dQueue: dQueue)
	}

	/// Load account data from disk; factory method for `AccountController`.
	internal static func load(keyPair: KeyPair, viewModel: any SocialViewModelDelegate, dQueue: DispatchQueue) -> AccountController? {
		guard let str = UserDefaults.standard.string(forKey: Self.PeerIDKey) else { return nil }
		guard let peerID = UUID(uuidString: str) else {
			flog(Self.LogTag, "our peer ID is not a UUID, deleting!")
			UserDefaults.standard.removeObject(forKey: Self.PeerIDKey)
			return nil
		}

		// TODO move sequence number into keychain
		let sequenceNumber: Int32
		if let sn = (UserDefaults.standard.object(forKey: Self.SequenceNumberKey) as? NSNumber)?.int32Value {
			sequenceNumber = sn
		} else {
			wlog(Self.LogTag, "Sequence Number is nil")
			// we set it to 0 s. t. it can be reset later by our normal reset process
			sequenceNumber = 0
		}

		return AccountController(peerID: peerID, sequenceNumber: sequenceNumber, keyPair: keyPair, viewModel: viewModel, dQueue: dQueue)
	}

	// MARK: Static Variables

	public var viewModel: any SocialViewModelDelegate

	/// Informed party when `AccountController` actions fail.
	public var delegate: AccountControllerDelegate?

	// MARK: Variables

	/// The crown juwels of the user and the second part of the user's identity.
	public let keyPair: KeyPair

	/// The identifier of the user on our social network.
	public let peerID: PeerID

	/// The user's unique identity on our social network.
	public var identity: PeereeIdentity { return PeereeIdentity(peerID: peerID, publicKey: keyPair.publicKey) }

	/// The email address associated with this account; if any.
	public private (set) var accountEmail: String? {
		didSet {
			if accountEmail != nil && accountEmail! != "" {
				UserDefaults.standard.set(accountEmail, forKey: AccountController.EmailKey)
			} else {
				UserDefaults.standard.removeObject(forKey: AccountController.EmailKey)
			}
		}
	}

	public var pinMatches: Set<PeerID> { return self.pinnedByPeers }

	/// Retrieves the full known public key of `peerID`, if available.
	public func publicKey(of peerID: PeereeCore.PeerID) -> Data? { return pinnedPeers[peerID] }

	/// Retrieves the full known identity of `peerID`.
	public func id(of peerID: PeereeCore.PeerID) throws -> PeereeIdentity {
		guard let publicKeyData = pinnedPeers[peerID] else {
			throw createApplicationError(localizedDescription: NSLocalizedString("Unknown peer.", comment: "Requested information about an unknown peer."))
		}

		return PeereeIdentity(peerID: peerID, publicKey: try AsymmetricPublicKey(from: publicKeyData, algorithm: PeereeIdentity.KeyAlgorithm, size: PeereeIdentity.KeySize))
	}

	/// Returns whether we have a pin match with that specific PeerID. Note, that this does NOT imply we have a match with a concrete PeerInfo of that PeerID, as that PeerInfo may be a malicious peer
	public func hasPinMatch(_ peerID: PeereeCore.PeerID) -> Bool {
		// it is enough to check whether we are pinned by peerID, as we only know that if we matched
		return pinnedByPeers.contains(peerID)
	}

	/// Returns whether we pinned that specific PeerIdentity.
	public func isPinned(_ id: PeereeIdentity) -> Bool {
		return pinnedPeers[id.peerID] == id.publicKeyData
	}

	/// Checks whether the pinning process is (already) running for `peerID`.
	public func isPinning(_ peerID: PeereeCore.PeerID) -> Bool {
		return pinningPeers.contains(peerID)
	}

	/// Pins a person and checks for a pin match.
	public func pin(_ id: PeereeIdentity) {
		let peerID = id.peerID
		guard !isPinned(id) && !isPinning(peerID) else { return }

		pinningPeers.insert(peerID)
		updateModels(of: [id])

		PinsAPI.putPin(pinnedID: peerID, pinnedKey: id.publicKeyData.base64EncodedData()) { (isPinMatch, error) in
			self.pinningPeers.remove(peerID)

			if let error {
				self.preprocessAuthenticatedRequestError(error)
				// possible HTTP errors:
				// 409: non-matching public key
				//
				switch error {
				case .httpError(409, _), .sessionTaskError(409?, _, _):
					// TODO: we should probably remove the peer
					self.delegate?.publicKeyMismatch(of: peerID)
				default:
					self.delegate?.pin(of: peerID, failedWith: error)
				}
				self.post(.pinFailed, peerID)
			} else if let isPinMatch {
				self.pin(id: id, isPinMatch: isPinMatch)
			} else {
				self.post(.pinFailed, peerID)
			}

			self.updateModels(of: [id])
		}
	}

	/// Removes the pin from a person.
	public func unpin(_ peerID: PeerID) {
		guard let id: PeereeIdentity = try? self.id(of: peerID),
			  !unpinningPeers.contains(peerID) && isPinned(id) else { return }

		unpinningPeers.insert(peerID)
		updateModels(of: [id])

		PinsAPI.deletePin(pinnedID: peerID) { (_, error) in
			self.unpinningPeers.remove(peerID)

			if let error {
				self.preprocessAuthenticatedRequestError(error)
				self.post(.unpinFailed, peerID)
			} else {
				self.removePin(from: id)
			}

			self.updateModels(of: [id])
		}
	}

	/// Reports the picture of a person as inappropriate.
	public func report(peerID: PeereeCore.PeerID, portrait: CGImage, portraitHash: Data, _ errorCallback: @escaping (Error) -> Void) {
		let hashString = portraitHash.hexString()
		let jpgData: Data

		do {
			jpgData = try portrait.jpgData(compressionQuality: AccountController.UploadCompressionQuality)
		} catch let error {
			errorCallback(error)
			return
		}

		ContentfilterAPI.putContentFilterPortraitReport(body: jpgData as Data, reportedPeerID: peerID, hash: hashString) { (_, error) in
			if let error {
				self.preprocessAuthenticatedRequestError(error)
				errorCallback(error)
			} else {
				let vm = self.viewModel

				DispatchQueue.main.async {
					vm.pendingObjectionableImageHashes[portraitHash] = Date()

					let save = vm.pendingObjectionableImageHashes
					self.dQueue.async {
						archiveObjectInUserDefs(save as NSDictionary, forKey: AccountController.PendingObjectionableImageHashesKey)
					}

					self.post(.peerReported, peerID)
				}
			}
		}
	}

	/// Downloads objectionable content hashes.
	public func refreshBlockedContent(_ errorCallback: @escaping (Error) -> Void) {
		guard self.lastObjectionableContentRefresh.addingTimeInterval(AccountController.ObjectionableContentRefreshThreshold) < Date() else { return }

		ContentfilterAPI.getContentFilterPortraitHashes(startDate: self.lastObjectionableContentRefresh) { (hexHashes, error) in
			if let error {
				self.preprocessAuthenticatedRequestError(error)
				errorCallback(error)
			} else if let hexHashes {
				let hashesAsData = Set<Data>(hexHashes.compactMap { Data(hexString: $0) })

				let nsPendingObjectionableImageHashes: NSDictionary? = unarchiveObjectFromUserDefs(Self.PendingObjectionableImageHashesKey, containing: [NSData.self, NSDate.self])
				let pendingObjectionableImageHashes = (nsPendingObjectionableImageHashes as? Dictionary<Data,Date> ?? Dictionary<Data,Date>()).filter { element in
					return !hashesAsData.contains(element.key)
				}

				archiveObjectInUserDefs(hashesAsData as NSSet, forKey: AccountController.ObjectionableImageHashesKey)
				archiveObjectInUserDefs(pendingObjectionableImageHashes as NSDictionary, forKey: AccountController.PendingObjectionableImageHashesKey)

				self.lastObjectionableContentRefresh = Date()
				UserDefaults.standard.set(self.lastObjectionableContentRefresh.timeIntervalSinceReferenceDate, forKey: AccountController.ObjectionableContentRefreshKey)

				DispatchQueue.main.async {
					self.viewModel.objectionableImageHashes = hashesAsData
					self.viewModel.pendingObjectionableImageHashes = pendingObjectionableImageHashes
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

		if var pendingRequests = updatePinStatusRequests[id.peerID] {
			completion.map {
				pendingRequests.append($0)
				updatePinStatusRequests[id.peerID] = pendingRequests
			}
			return
		} else {
			updatePinStatusRequests[id.peerID] = [completion ?? {_ in }]
		}

		let pinPublicKey = id.publicKeyData.base64EncodedData()

		PinsAPI.getPin(pinnedID: id.peerID, pinnedKey: pinPublicKey) { (pinStatus, error) in
			defer {
				let pinState = self.pinState(of: id.peerID)
				self.updatePinStatusRequests[id.peerID]?.forEach { callback in
					callback(pinState)
				}

				self.updatePinStatusRequests.removeValue(forKey: id.peerID)
			}

			if let error {
				self.preprocessAuthenticatedRequestError(error)
				return
			}

			if let pinStatus {
				switch pinStatus {
				case 0:
					self.pin(id: id, isPinMatch: false)
				case 1:
					self.pin(id: id, isPinMatch: true)
				default:
					self.removePin(from: id)
				}

				self.updateModels(of: [id])
			}
		}
	}

	/// Changes the email address of the account or removes it if `email` is the empty string.
	public func update(email: String, _ completion: @escaping (Error?) -> Void) {
		guard email != "" else { deleteEmail(completion); return }
		AccountAPI.putAccountEmail(email: email) { (_, error) in
			if let error {
				self.preprocessAuthenticatedRequestError(error)
			} else {
				self.accountEmail = email
			}
			completion(error)
		}
	}

	/// Removes the email address from the account.
	public func deleteEmail(_ completion: @escaping (Error?) -> Void) {
		AccountAPI.deleteAccountEmail { (_, error) in
			if let error {
				self.preprocessAuthenticatedRequestError(error)
			} else {
				self.accountEmail = nil
			}
			completion(error)
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
			flog(Self.LogTag, "Cannot compute signature: \(error)")
			return ""
		}
	}

	// MARK: - Private

	/// Creates the AccountController singleton and installs it in the rest of the app.
	private init(peerID: PeerID, sequenceNumber: Int32, keyPair: KeyPair, viewModel: any SocialViewModelDelegate, dQueue: DispatchQueue) {
		self.peerID = peerID
		self.sequenceNumber = sequenceNumber
		self.keyPair = keyPair
		self.viewModel = viewModel
		self.dQueue = dQueue

		let nsPinnedBy: NSSet? = unarchiveObjectFromUserDefs(Self.PinnedByPeersKey, containing: [NSUUID.self])
		self.pinnedByPeers = nsPinnedBy as? Set<PeerID> ?? Set()

		let nsPinned: NSDictionary? = unarchiveObjectFromUserDefs(Self.PinnedPeersKey, containing: [NSUUID.self, NSData.self])
		self.pinnedPeers = nsPinned as? [PeerID : Data] ?? [PeereeCore.PeerID : Data]()

		let lastRefreshInterval = UserDefaults.standard.double(forKey: Self.ObjectionableContentRefreshKey)
		self.lastObjectionableContentRefresh = Date(timeIntervalSinceReferenceDate: lastRefreshInterval)

		accountEmail = UserDefaults.standard.string(forKey: AccountController.EmailKey)

		let models: [PeereeIdentity] = pinnedPeers.compactMap { (peerID, publicKeyData) in
			try? PeereeIdentity(peerID: peerID, publicKeyData: publicKeyData)
		}

		DispatchQueue.main.async {
			viewModel.userPeerID = peerID
			viewModel.accountExists = .on
		}

		self.updateModels(of: models)
	}

	// MARK: Static Constants

	// Log tag.
	private static let LogTag = "Account"

	/// Key to our identity in UserDefaults
	private static let PeerIDKey = "PeerIDKey"

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

	/// Refresh objectionable content every day at most (or when the app is killed).
	private static let ObjectionableContentRefreshThreshold: TimeInterval = 60 * 60 * 24

	/// The number added to the current sequence number after each server chat operation.
	private static let SequenceNumberIncrement: Int32 = 13

	/// DispatchQueue injected by AccountControllerFactory.
	private let dQueue: DispatchQueue

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

	// In-flight `getPin` requests.
	private var updatePinStatusRequests = [PeereeCore.PeerID: [(PinState) -> Void]]()

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
			SocialPersonData(peerID: id.peerID, pinState: self.pinState(of: id.peerID))
		}

		DispatchQueue.main.async {
			for model in models {
				_ = self.viewModel.addPersona(of: model.peerID, with: model.pinState)
			}
		}
	}

	/// Request a new sequence number, since we may have run out of sync with the server.
	private func resetSequenceNumber() {
		wlog(Self.LogTag, "resetting sequence number")
		AuthenticationAPI.deleteAccountSecuritySequenceNumber { (sequenceNumberDataCipher, error) in
			guard let sequenceNumberDataCipher else {
				if let error {
					elog(Self.LogTag, "resetting sequence number failed: \(error.localizedDescription)")
					self.delegate?.sequenceNumberResetFailed(error: error)
				}
				return
			}

			self.sequenceNumber = sequenceNumberDataCipher
			self.delegate?.sequenceNumberReset()
		}
	}

	/// resets sequence number to state before request if the request did not reach the server
	private func preprocessAuthenticatedRequestError(_ errorResponse: ErrorResponse) {
		switch errorResponse {
		case .httpError(403, let messageData):
			elog(Self.LogTag, "Unauthorized: \(messageData.map { String(data: $0, encoding: .utf8) ?? "(decode failed) code 403." } ?? "code 403.")")
			self.resetSequenceNumber()
		case .parseError(_):
			elog(Self.LogTag, "Response could not be parsed.")
			break
		case .sessionTaskError(let statusCode, _, let error):
			elog(Self.LogTag, "Network error \(statusCode ?? -1) occurred: \(error.localizedDescription)")
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
	internal func clearLocalData(_ completion: @escaping () -> Void) {
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
			try keyPair.removeFromKeychain()
		} catch let error {
			flog(Self.LogTag, "Could not delete keychain items. Creation of new identity will probably fail. Error: \(error.localizedDescription)")
		}

		SwaggerClientAPI.dataSource = nil
		DispatchQueue.main.async {
			self.viewModel.clear()
			self.dQueue.async { completion() }
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
			elog(Self.LogTag, "Unknown PeerID \(peerID) in updatePinStatus(): \(error)")
			completion?(.unpinned)
		}
	}
}
