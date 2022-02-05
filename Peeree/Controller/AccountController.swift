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

public protocol AccountControllerDelegate {
	func pin(of peerID: PeerID, failedWith error: Error)
	func publicKeyMismatch(of peerID: PeerID)
	func sequenceNumberResetFailed(error: ErrorResponse)
}

/**
 * Central singleton for managing all actions according to communication with the Peeree server.
 * Do NOT use the network calls in DefaultAPI directly, as then the sequence number won't be updated appropriately
 */
public class AccountController: SecurityDataSource {
	/// User defaults key for pinned peers dictionary
	static private let PinnedPeersKey = "PinnedPeers"
	/// User defaults key for pinned by peers dictionary
	static private let PinnedByPeersKey = "PinnedByPeers"
	/// User defaults key for user's email
	static private let EmailKey = "Email"
	/// User defaults key for sequence number
	static private let SequenceNumberKey = "SequenceNumber"
	/// User defaults key for objectionable image hashes
	static private let ObjectionableImageHashesKey = "ObjectionableImageHashes"
	/// User defaults key for reported and not yet objectionable image hashes
	static private let PendingObjectionableImageHashesKey = "PendingObjectionableImageHashesKey"
	/// User defaults key for objectionable content refresh timestamp
	static private let ObjectionableContentRefreshKey = "ObjectionableContentRefresh"
	/// JPEG compression quality for portrait report uploads.
	static private let UploadCompressionQuality: CGFloat = 0.3

	/// Keychain property
	private static let PrivateKeyTag = "com.peeree.keys.restkey.private".data(using: .utf8)!
	/// Keychain property
	private static let PublicKeyTag = "com.peeree.keys.restkey.public".data(using: .utf8)!
	/// Keychain property
	private static let KeyLabel = "Peeree Identity"
	/// Keychain property
	public static let KeyType = kSecAttrKeyTypeEC
	/// Keychain property
	public static let KeySize = 256 // SecKeySizes.secp256r1.rawValue as AnyObject, only available on macOS...

	/// Key to our identity in UserDefaults
	private static let PeerIDKey = "PeerIDKey"

	/// refresh objectionable content every day at most (or when the app is killed)
	static let ObjectionableContentRefreshThreshold: TimeInterval = 60 * 60 * 24
	
	public static let shared = AccountController()
	
	public enum Notifications: String {
		public enum NotificationInfoKey: String {
			case peerID
		}
		case pinned, pinningStarted, pinFailed, pinMatch
		case pinStateUpdated, unpinned, unpinFailed
		case accountCreated, accountDeleted
		case peerReported
		
		func post(_ peerID: PeerID) {
			postAsNotification(object: AccountController.shared, userInfo: [NotificationInfoKey.peerID.rawValue : peerID])
		}
	}
	
	/*
	 store pinned public key along with peerID as
	 1. Alice pins Bob
	 2. Eve advertises Bob's peerID with her public key
	 3. Alice validates Bob's peerID with Eve's public key and thinks she met Bob again
	 4. Eve convinced Alice successfully that she is Bob
	*/
	
	/// stores acknowledged pinned peers and their public keys
	private var pinnedPeers: SynchronizedDictionary<PeerID, Data>
	/// stores acknowledged pin matched peers
	private var pinnedByPeers: SynchronizedSet<PeerID>
	
	private var pinningPeers = SynchronizedSet<PeerID>(queueLabel: "\(BundleID).pinningPeers")

	/// the crown juwels of the user and the second part of the user's identity
	private (set) var keyPair: KeyPair?

	/// the unique identity of the user on our social network
	private (set) var peerID: PeerID

	var identity: PeereeIdentity? { return keyPair.map { PeereeIdentity(peerID: peerID, publicKey: $0.publicKey) } }

	// only access these only from the main thread!
	private var objectionableImageHashes: Set<Data>
	private var pendingObjectionableImageHashes: [Data : Date]
	private var lastObjectionableContentRefresh: Date
	
	private func resetSequenceNumber() {
		NSLog("WARN: resetting sequence number")
		AuthenticationAPI.deleteAccountSecuritySequenceNumber { (_sequenceNumberDataCipher, _error) in
			guard let sequenceNumberDataCipher = _sequenceNumberDataCipher else {
				if let error = _error {
					NSLog("ERROR: resetting sequence number failed: \(error.localizedDescription)")
					self.delegate?.sequenceNumberResetFailed(error: error)
				}
				return
			}
			
			self._sequenceNumber = sequenceNumberDataCipher
		}
	}
	
	private static let SequenceNumberIncrement: Int32 = 13
	private var _sequenceNumber: Int32? {
		didSet {
			if let sequenceNumber = _sequenceNumber {
				UserDefaults.standard.set(NSNumber(value: sequenceNumber), forKey: AccountController.SequenceNumberKey)
			} else {
				UserDefaults.standard.removeObject(forKey: AccountController.SequenceNumberKey)
			}
		}
	}
	
	private (set) var accountEmail: String? {
		didSet {
			if accountEmail != nil && accountEmail! != "" {
				UserDefaults.standard.set(accountEmail, forKey: AccountController.EmailKey)
			} else {
				UserDefaults.standard.removeObject(forKey: AccountController.EmailKey)
			}
		}
	}

	public var accountExists: Bool { return _sequenceNumber != nil }

	private (set) var isCreatingAccount = false
	private (set) var isDeletingAccount = false

	public var delegate: AccountControllerDelegate?
	
	public func publicKey(of peerID: PeerID) -> Data? { return pinnedPeers[peerID] }
	
	/// Returns whether we have a pin match with that specific PeerID. Note, that this does NOT imply we have a match with a concrete PeerInfo of that PeerID, as that PeerInfo may be a malicious peer
	public func hasPinMatch(_ peerID: PeerID) -> Bool {
		// it is enough to check whether we are pinned by peerID, as we only know that if we matched
		return pinnedByPeers.contains(peerID)
	}
	
	/// Returns whether we pinned that specific PeerID. Note, that this does NOT imply we pinned that person who's telling us he has this PeerID, as that PeerInfo may be a malicious peer. Thus, always check verification status of PeerInfo additionally
	public func isPinned(_ id: PeereeIdentity) -> Bool {
		return pinnedPeers.contains { $0.0 == id.peerID && $0.1 == id.publicKeyData }
	}
	
	public func isPinning(_ peerID: PeerID) -> Bool {
		return pinningPeers.contains(peerID)
	}

	public func pin(_ id: PeereeIdentity) {
		guard accountExists else { return }

		let peerID = id.peerID
		guard !isPinned(id) && !(pinningPeers.contains(peerID)) else { return }
		
		self.pinningPeers.insert(peerID)
		Notifications.pinningStarted.post(peerID)
		PinsAPI.putPin(pinnedID: peerID, pinnedKey: id.publicKeyData.base64EncodedData()) { (_isPinMatch, _error) in
			self.pinningPeers.remove(peerID)
			if let error = _error {
				self.preprocessAuthenticatedRequestError(error)
				// possible HTTP errors:
				// 409: non-matching public key
				//
				switch error {
				case .httpError(409, _), .sessionTaskError(409?, _, _):
					self.delegate?.publicKeyMismatch(of: peerID)
				default:
					self.delegate?.pin(of: peerID, failedWith: error)
				}
				Notifications.pinFailed.post(peerID)
			} else if let isPinMatch = _isPinMatch  {
				self.pin(id: id, isPinMatch: isPinMatch)
			} else {
				Notifications.pinFailed.post(peerID)
			}
		}
	}

	public func unpin(id: PeereeIdentity) {
		guard accountExists && isPinned(id) else { return }
		let peerID = id.peerID
		
		PinsAPI.deletePin(pinnedID: peerID) { (_, _error) in
			if let error = _error {
				self.preprocessAuthenticatedRequestError(error)
				Notifications.unpinFailed.post(peerID)
			} else {
				self.removePin(from: id)
				Notifications.unpinned.post(peerID)
			}
		}
	}
	
	public enum ContentClassification {
		case objectionable, pending, none
	}
	
	public func containsObjectionableContent(imageHash: Data, completion: @escaping (ContentClassification) -> Void) {
		DispatchQueue.main.async {
			completion(self.objectionableImageHashes.contains(imageHash) ? .objectionable : (self.pendingObjectionableImageHashes[imageHash] != nil ? .pending : .none))
		}
	}

	public func report(model: PeerViewModel, errorCallback: @escaping (Error) -> Void) {
		guard let portrait = model.cgPicture, let hash = model.pictureHash else { return }
		
		let hashString = hash.hexString()
		let jpgData: Data

		do {
			#if os(iOS)
			if let data = model.picture?.jpegData(compressionQuality: AccountController.UploadCompressionQuality) {
				jpgData = data
				let str = jpgData[jpgData.startIndex...jpgData.startIndex.advanced(by: 20)].hexString()
				NSLog("INFO: sending \(str)")
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
					self.pendingObjectionableImageHashes[hash] = Date()
					archiveObjectInUserDefs(self.pendingObjectionableImageHashes as NSDictionary, forKey: AccountController.PendingObjectionableImageHashesKey)
					PeerViewModelController.modify(peerID: model.peerID) { workModel in
						workModel.pictureClassification = .pending
						Notifications.peerReported.post(model.peerID)
					}
				}
			}
		}
	}
	
	public func refreshBlockedContent(errorCallback: @escaping (Error) -> Void) {
		guard self.lastObjectionableContentRefresh.addingTimeInterval(AccountController.ObjectionableContentRefreshThreshold) < Date() else { return }
		ContentfilterAPI.getContentFilterPortraitHashes(startDate: self.lastObjectionableContentRefresh) { (_hexHashes, _error) in
			if let error = _error {
				self.preprocessAuthenticatedRequestError(error)
				errorCallback(error)
			} else if let hexHashes = _hexHashes {
				DispatchQueue.main.async {
					for hexHash in hexHashes {
						if let decodedHash = Data(hexString: hexHash) {
							self.objectionableImageHashes.insert(decodedHash)
							self.pendingObjectionableImageHashes.removeValue(forKey: decodedHash)
						} else {
							NSLog("WARN: Decoding objectionable image hash '\(hexHash)' failed.")
						}
					}
					self.lastObjectionableContentRefresh = Date()
					UserDefaults.standard.set(self.lastObjectionableContentRefresh.timeIntervalSinceReferenceDate, forKey: AccountController.ObjectionableContentRefreshKey)
					archiveObjectInUserDefs(self.objectionableImageHashes as NSSet, forKey: AccountController.ObjectionableImageHashesKey)
					archiveObjectInUserDefs(self.pendingObjectionableImageHashes as NSDictionary, forKey: AccountController.PendingObjectionableImageHashesKey)
				}
			} else {
				errorCallback(ErrorResponse.parseError(nil))
			}
		}
	}

	private func pin(id: PeereeIdentity, isPinMatch: Bool) {
		guard accountExists else { return }

		self.pinnedPeers.accessAsync { (dictionary) in
			let peerID = id.peerID
			if dictionary[peerID] != id.publicKeyData {
				dictionary[peerID] = id.publicKeyData
				// access the set on the queue to ensure the last peerID is also included
				archiveObjectInUserDefs(dictionary as NSDictionary, forKey: AccountController.PinnedPeersKey)
				
				Notifications.pinned.post(peerID)
			}
			
			if isPinMatch {
				self.pinnedByPeers.accessAsync { (set) in
					if !set.contains(peerID) {
						set.insert(peerID)
						// access the set on the queue to ensure the last peerID is also included
						archiveObjectInUserDefs(set as NSSet, forKey: AccountController.PinnedByPeersKey)

						// post this on the main queue
						Notifications.pinMatch.post(peerID)
					}
				}
			}
		}
	}

	private func removePin(from id: PeereeIdentity) {
		let peerID = id.peerID
		self.pinnedPeers.accessAsync { (dictionary) in
			dictionary.removeValue(forKey: peerID)
			// access the set on the queue to ensure the last peerID is also included
			archiveObjectInUserDefs(dictionary as NSDictionary, forKey: AccountController.PinnedPeersKey)
			Notifications.pinFailed.post(peerID)
		}
		
		self.pinnedByPeers.accessAsync { (set) in
			if set.remove(peerID) != nil {
				// access the set on the queue to ensure the last peerID is also included
				archiveObjectInUserDefs(set as NSSet, forKey: AccountController.PinnedByPeersKey)
			}
		}
	}
	
	private func clearPins() {
		self.pinningPeers.removeAll()
		
		self.pinnedPeers.accessAsync { (dictionary) in
			dictionary.removeAll()
			// access the set on the queue to ensure the last peerID is also included
			archiveObjectInUserDefs(dictionary as NSDictionary, forKey: AccountController.PinnedPeersKey)
		}
		
		self.pinnedByPeers.accessAsync { (set) in
			set.removeAll()
			// access the set on the queue to ensure the last peerID is also included
			archiveObjectInUserDefs(set as NSSet, forKey: AccountController.PinnedByPeersKey)
		}
	}

	public func updatePinStatus(of id: PeereeIdentity) {
		guard accountExists else { return }
		// attack scenario: Eve sends pin match indication to Alice, but Alice only asks server, if she pinned Eve in the first place => Eve can observe Alice's internet communication and can figure out, whether Alice pinned her, depending on whether Alice' asked the server after the indication.
		// thus, we (Alice) have to at least once validate with the server, even if we know, that we did not pin Eve
		// This is achieved through the hasPinMatch query, as this will always fail, if we do not have a true match, thus we query ALWAYS the server when we receive a pin match indication. If flooding attack (Eve sends us dozens of indications) gets serious, implement above behaviour, that we only validate once
		// we can savely ignore this if we already know we have a pin match
		guard !hasPinMatch(id.peerID) else { return }

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
				Notifications.pinStateUpdated.post(id.peerID)
			}
		}
	}
	
	public func createAccount(completion: @escaping (Error?) -> Void) {
		guard !isCreatingAccount else { return } // TODO: data race (accessed on different queue below)
		isCreatingAccount = true
		_sequenceNumber = nil // we are not responsible here to ensure that no account already exists and need to not send this sequence number as our public key
		do {
			// try to remove the old key, just to be sure
			try? KeychainStore.removeFromKeychain(tag: AccountController.PublicKeyTag, keyType: AccountController.KeyType, keyClass: kSecAttrKeyClassPublic, size: AccountController.KeySize)
			try? KeychainStore.removeFromKeychain(tag: AccountController.PrivateKeyTag, keyType: AccountController.KeyType, keyClass: kSecAttrKeyClassPrivate, size: AccountController.KeySize)

			keyPair = try KeyPair(label: AccountController.KeyLabel, privateTag: AccountController.PrivateKeyTag, publicTag: AccountController.PublicKeyTag, type: AccountController.KeyType, size: AccountController.KeySize, persistent: true)
		} catch let error {
			completion(error)
		}
	
		AccountAPI.putAccount(email: accountEmail) { (_account, _error) in
			var completionError: Error?
			defer {
				self.isCreatingAccount = false
				completion(completionError)
				if completionError == nil {
					Notifications.accountCreated.post(self.peerID)
				}
			}
			
			guard let account = _account else {
				completionError = _error ?? NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Server did provide malformed or no account information", comment: "Error when an account creation request response is malformed")])
				return
			}

			self._sequenceNumber = account.sequenceNumber
			self.peerID = account.peerID // TODO: this is a data race, but I don't want to put PeerID on a special queue
			UserDefaults.standard.set(account.peerID.uuidString, forKey: AccountController.PeerIDKey)
			completionError = nil
		}
	}
	
	public func deleteAccount(completion: @escaping (Error?) -> Void) {
		guard accountExists, !isDeletingAccount else { return }
		isDeletingAccount = true
		let oldPeerID = peerID

		AccountAPI.deleteAccount { (_, _error) in
			var reportedError = _error
			if let error = _error {
				switch error {
				case .httpError(403, let messageData):
					NSLog("ERROR: Our account seems to not exist on the server. Will silently delete local references. Body: \(String(describing: messageData))")
					reportedError = nil
				default:
					self.preprocessAuthenticatedRequestError(error)
				}
			}
			if reportedError == nil {
				self.accountEmail = nil
				self._sequenceNumber = nil
				self.clearPins()
				do {
					try KeychainStore.removeFromKeychain(tag: AccountController.PublicKeyTag, keyType: AccountController.KeyType, keyClass: kSecAttrKeyClassPublic, size: AccountController.KeySize)
					try KeychainStore.removeFromKeychain(tag: AccountController.PrivateKeyTag, keyType: AccountController.KeyType, keyClass: kSecAttrKeyClassPrivate, size: AccountController.KeySize)
				} catch let error {
					NSLog("ERROR: Could not delete keychain items. Creation of new identity will probably fail. Error: \(error.localizedDescription)")
				}
				DispatchQueue.main.async {
					PeerViewModelController.remove(peerID: oldPeerID)
					Notifications.accountDeleted.postAsNotification(object: self)
				}
			}
			self.isDeletingAccount = false
			completion(reportedError)
		}
	}
	
	public func update(email: String, completion: @escaping (Error?) -> Void) {
		guard accountExists else { return }
		guard email != "" else { deleteEmail(completion: completion); return }
		AccountAPI.putAccountEmail(email: email) { (_, _error) in
			if let error = _error {
				self.preprocessAuthenticatedRequestError(error)
			} else {
				self.accountEmail = email
			}
			completion(_error)
		}
	}
	
	public func deleteEmail(completion: @escaping (Error?) -> Void) {
		guard accountExists else { return }
		AccountAPI.deleteAccountEmail { (_, _error) in
			if let error = _error {
				self.preprocessAuthenticatedRequestError(error)
			} else {
				self.accountEmail = nil
			}
			completion(_error)
		}
	}
	
	// MARK: SecurityDelegate
	
	public func getPeerID() -> String {
		return peerID.uuidString
	}
	
	public func getSignature() -> String {
		return (try? computeSignature()) ?? (try? keyPair?.externalPublicKey().base64EncodedString()) ?? ""
	}
	
	// MARK: Private Functions
	
	private init() {
		peerID = UserDefaults.standard.string(forKey: AccountController.PeerIDKey).map { UUID(uuidString: $0) ?? PeerID() } ?? PeerID()
		self.keyPair = try? KeyPair(fromKeychainWith: AccountController.KeyLabel, privateTag: AccountController.PrivateKeyTag, publicTag: AccountController.PublicKeyTag, type: AccountController.KeyType, size: AccountController.KeySize)
		// TODO PERFORMANCE (startup time): read from UserDefs and decode on background queue
		let nsPinnedBy: NSSet? = unarchiveObjectFromUserDefs(AccountController.PinnedByPeersKey)
		pinnedByPeers = SynchronizedSet(queueLabel: "\(BundleID).pinnedByPeers", set: nsPinnedBy as? Set<PeerID> ?? Set())
		let nsPinned: NSDictionary? = unarchiveObjectFromUserDefs(AccountController.PinnedPeersKey)
		pinnedPeers = SynchronizedDictionary(queueLabel: "\(BundleID).pinnedPeers", dictionary: nsPinned as? [PeerID : Data] ?? [PeerID : Data]())
		let nsObjectionableImageHashes: NSSet? = unarchiveObjectFromUserDefs(AccountController.ObjectionableImageHashesKey)
		objectionableImageHashes = nsObjectionableImageHashes as? Set<Data> ?? Set()
		let nsPendingObjectionableImageHashes: NSDictionary? = unarchiveObjectFromUserDefs(AccountController.PendingObjectionableImageHashesKey)
		pendingObjectionableImageHashes = nsPendingObjectionableImageHashes as? Dictionary<Data,Date> ?? Dictionary<Data,Date>()
		lastObjectionableContentRefresh = Date(timeIntervalSinceReferenceDate: UserDefaults.standard.double(forKey: AccountController.ObjectionableContentRefreshKey))
		accountEmail = UserDefaults.standard.string(forKey: AccountController.EmailKey)
		// TODO move sequence number into keychain
		_sequenceNumber = (UserDefaults.standard.object(forKey: AccountController.SequenceNumberKey) as? NSNumber)?.int32Value
		SwaggerClientAPI.dataSource = self
	}
	
	/// resets sequence number to state before request if the request did not reach the server
	private func preprocessAuthenticatedRequestError(_ errorResponse: ErrorResponse) {
		switch errorResponse {
		case .httpError(403, let messageData):
			NSLog("ERROR: Unauthorized: \(messageData.map { String(data: $0, encoding: .utf8) ?? "(decode failed) code 403." } ?? "code 403.")")
			self.resetSequenceNumber()
		case .parseError(_):
			NSLog("ERROR: Response could not be parsed.")
			break
		case .sessionTaskError(let statusCode, _, let error):
			NSLog("ERROR: Network error \(statusCode ?? -1) occurred: \(error.localizedDescription)")
			if (error as NSError).domain == NSURLErrorDomain {
				if let sequenceNumber = _sequenceNumber {
					// we did not even reach the server, so we have to decrement our sequenceNumber again
					_sequenceNumber = sequenceNumber.subtractingReportingOverflow(AccountController.SequenceNumberIncrement).partialValue
				}
			}
			if statusCode == 403 { // forbidden
				// the signature was invalid, so request a new sequenceNumber
				self.resetSequenceNumber()
			}
		default:
			break
		}
	}
	
	private func computeSignature() throws -> String {
		guard _sequenceNumber != nil, let sequenceNumberData = String(_sequenceNumber!).data(using: .utf8), let keyPair = keyPair else {
			throw NSError(domain: "Peeree", code: -2, userInfo: nil)
		}
		
		_sequenceNumber = _sequenceNumber!.addingReportingOverflow(AccountController.SequenceNumberIncrement).partialValue
		return try keyPair.sign(message: sequenceNumberData).base64EncodedString()
	}
}

extension PeereeIdentity {
	public var pinMatched: Bool { AccountController.shared.hasPinMatch(peerID) }
	public var pinned: Bool { AccountController.shared.isPinned(self) }
}
