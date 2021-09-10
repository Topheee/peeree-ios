//
//  ServerChatController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 12.05.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import Foundation
import MatrixSDK

let serverChatDomain = "chat.peeree.de"

func serverChatUserId(for peerID: PeerID) -> String {
	return "@\(serverChatUserName(for: peerID)):\(serverChatDomain)"
}

func peerIDFrom(serverChatUserId userId: String) -> PeerID? {
	guard userId.count > 0,
		  let atIndex = userId.firstIndex(of: "@"),
		  let colonIndex = userId.firstIndex(of: ":") else { return nil }

	return PeerID(uuidString: String(userId[userId.index(after: atIndex)..<colonIndex]))
}

func serverChatUserName(for peerID: PeerID) -> String {
	return peerID.uuidString.lowercased()
}

func unexpectedNilError() -> Error {
	return createApplicationError(localizedDescription: "Found unexpected nil object", code: -1)
}

func unexpectedEnumValueError() -> Error {
	return createApplicationError(localizedDescription: "Found unexpected enumeration case", code: -1)
}

final class ServerChatController {
	static let homeServerURL = URL(string: "https://\(serverChatDomain):8448/")!
	static var userId: String { return serverChatUserId(for: UserPeerManager.instance.peerID) } // TODO race condition and performance (but cannot be let because our peerID may change)
	// we need to keep a strong reference to the client s.t. it is not destroyed while requests are in flight
	static let globalRestClient = MXRestClient(homeServer: homeServerURL) { _data in
		NSLog("ERROR: matrix certificate rejected: \(String(describing: _data))")
		return false
	}

	// MARK: Singleton Lifecycle

	/// access only from main thread!
	private static var _instance: ServerChatController? = nil
	private static var creatingInstanceCallbacks = [(Result<ServerChatController, Error>) -> Void]()
	private static var creatingInstanceOnlyLoginRequests = [Bool]()

	static private func reportCreatingInstance(result: Result<ServerChatController, Error>) {
		DispatchQueue.main.async {
			creatingInstanceCallbacks.forEach { $0(result) }
			creatingInstanceOnlyLoginRequests.removeAll()
			creatingInstanceCallbacks.removeAll()
		}
	}

	static func withInstance(getter: @escaping (ServerChatController?) -> Void) {
		DispatchQueue.main.async { getter(_instance) }
	}

	static func getOrSetupInstance(onlyLogin: Bool = false, completion: @escaping (Result<ServerChatController, Error>) -> Void) {
		DispatchQueue.main.async {
			if let instance = _instance {
				completion(.success(instance))
				return
			}

			creatingInstanceCallbacks.append(completion)
			creatingInstanceOnlyLoginRequests.append(onlyLogin)
			guard creatingInstanceCallbacks.count == 1 else { return }

			login { loginResult in
				DispatchQueue.main.async {
					switch loginResult {
					case .success(let credentials):
						setupInstance(with: credentials)
					case .failure(let error):
						var reallyOnlyLogin = true
						creatingInstanceOnlyLoginRequests.forEach { reallyOnlyLogin = reallyOnlyLogin && $0 }
						guard !reallyOnlyLogin else {
							reportCreatingInstance(result: .failure(error))
							return
						}
						NSLog("WARN: server chat login failed: \(error.localizedDescription)")
						createAccount { createAccountResult in
							switch createAccountResult {
							case .success(let credentials):
								setupInstance(with: credentials)
							case .failure(let error):
								reportCreatingInstance(result: .failure(error))
							}
						}
					}
				}
			}
		}
	}

	private static func setupInstance(with credentials: MXCredentials) {
		let c = ServerChatController(credentials: credentials)
		c.start { _error in
			if let error = _error {
				reportCreatingInstance(result: .failure(error))
			} else {
				DispatchQueue.main.async {
					_instance = c
					reportCreatingInstance(result: .success(c))
				}
			}
		}
	}

	private static func createAccount(completion: @escaping (Result<MXCredentials, Error>) -> Void) {
		let peerID = UserPeerManager.instance.peerID
		let username = serverChatUserName(for: peerID)
		var passwordRawData: Data
		do {
			passwordRawData = try generateRandomData(length: Int.random(in: 24...26))
		} catch let error {
			completion(.failure(error))
			return
		}
		var passwordData = passwordRawData.base64EncodedData()
		assert(String(data: passwordData, encoding: .utf8) == passwordRawData.base64EncodedString())
		do {
			try persistPasswordInKeychain(passwordData)
			passwordData.resetBytes(in: 0..<passwordData.count)
		} catch let error {
			completion(.failure(error))
			return
		}

		globalRestClient.register(loginType: .dummy, username: username, password: passwordRawData.base64EncodedString()) { response in
			switch response {
			case .failure(let error):
				do {
					try ServerChatController.removePasswordFromKeychain()
				} catch {
					NSLog("ERROR: Could not remove password from keychain after failed registration: \(error.localizedDescription)")
				}
				completion(.failure(error))
			case .success(let credentials):
				// TODO save device_id and re-use it for subsequent logins in order to support E2E encryption
				completion(.success(credentials))
			@unknown default:
				completion(.failure(unexpectedEnumValueError()))
			}
		}
		passwordRawData.resetBytes(in: 0..<passwordRawData.count)
	}

	private static func login(completion: @escaping (Result<MXCredentials, Error>) -> Void) {
		let password: String
		do {
			password = try passwordFromKeychain()
		} catch let error {
			completion(.failure(error))
			return
		}
		globalRestClient.login(parameters: ["type" : kMXLoginFlowTypePassword,
											"identifier" : ["type" : kMXLoginIdentifierTypeUser, "user" : userId],
											"password" : password,
											// Patch: add the old login api parameters to make dummy login still working
											"user" : userId,
											// probably a bad idea for the far future to use the userId as the device_id here, but hell yeah
											"device_id" : userId]) { response in
//		this crappy shit doesn't (re-)store a persistent device_id:
//		globalRestClient.login(type: .password, username: userId, password: password) { response in
			if let error = response.error as NSError?,
			   let mxErrCode = error.userInfo[kMXErrorCodeKey] as? String,
			   mxErrCode == "M_INVALID_USERNAME" {
				NSLog("ERROR: Our account seems to be deleted. Removing local password to be able to re-register.")
				do {
					try ServerChatController.removePasswordFromKeychain()
				} catch let pwError {
					NSLog("WARN: Removing local password failed, not an issue if not existant: \(pwError.localizedDescription)")
				}
			}
			// could be that easy:
//			completion(response.toResult())
			guard let json = response.value else {
				NSLog("ERROR: Login response is nil.")
				completion(.failure(unexpectedNilError()))
				return
			}
			guard let loginResponse = MXLoginResponse(fromJSON: json) else {
				completion(.failure(createApplicationError(localizedDescription: "ERROR: Cannot create login response from JSON \(json).")))
				return
			}
			let credentials = MXCredentials(loginResponse: loginResponse, andDefaultCredentials: globalRestClient.credentials)
			completion(.success(credentials))
		}
	}

	/// tries to leave (and forget [once supported]) <code>rooms</code>, ignoring any errors
	private func forget(room: MXRoom, completion: @escaping (Error?) -> Void) {
		room.leave { response in
			// TODO implement [forget](https://matrix.org/docs/spec/client_server/r0.6.1#id294) API call once it is available in matrix-ios-sdk
			completion(response.error)
		}
	}

	/// tries to leave (and forget [once supported]) <code>rooms</code>, ignoring any errors
	private func forget(rooms: [MXRoom], completion: @escaping () -> Void) {
		var leftoverRooms = rooms // inefficient as hell: always creates a whole copy of the array
		guard let room = leftoverRooms.popLast() else {
			completion()
			return
		}
		room.leave { response in
			if let error = response.error {
				NSLog("ERROR: Failed leaving room: \(error.localizedDescription)")
			}
			// TODO implement [forget](https://matrix.org/docs/spec/client_server/r0.6.1#id294) API call once it is available in matrix-ios-sdk
			self.forget(rooms: leftoverRooms, completion: completion)
		}
	}

	func deleteAccount(completion: @escaping (Error?) -> Void) {
		let password: String
		do {
			password = try ServerChatController.passwordFromKeychain()
		} catch let error {
			completion(error)
			return
		}
		forget(rooms: session.rooms) {
			self.session.deactivateAccount(withAuthParameters: ["type" : kMXLoginFlowTypePassword, "user" : ServerChatController.userId, "password" : password], eraseAccount: true) { response in
				guard response.isSuccess else { completion(response.error); return }

				do {
					try ServerChatController.removePasswordFromKeychain()
				} catch let error {
					NSLog("ERROR: \(error.localizedDescription)")
				}
				// it seems we need to log out after we deleted the account
				self.logout { _error in
					_error.map { NSLog("ERROR: Logout after account deletion failed: \($0.localizedDescription)") }
					// do not escalate the error of the logout, as it doesn't mean we didn't successfully deactivated the account
					completion(nil)
				}
			}
		}
	}

	// MARK: Keychain Access

	private static func persistPasswordInKeychain(_ password: Data) throws {
		let homeServer = homeServerURL.absoluteString
		let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
									kSecAttrAccount as String: userId,
									kSecAttrServer as String: homeServer,
									kSecValueData as String: password]
		try SecKey.check(status: SecItemAdd(query as CFDictionary, nil), localizedError: NSLocalizedString("Adding Server Chat credentials to Keychain failed", comment: "SecItemAdd failed"))
	}

	private static func passwordFromKeychain() throws -> String {
		let homeServer = homeServerURL.absoluteString
		let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
									kSecAttrServer as String: homeServer,
									kSecAttrAccount as String: userId,
									kSecMatchLimit as String: kSecMatchLimitOne,
									kSecReturnData as String: true]
		var item: CFTypeRef?
		try SecKey.check(status: SecItemCopyMatching(query as CFDictionary, &item), localizedError: NSLocalizedString("Reading key from keychain failed.", comment: "Attempt to read a keychain item failed."))

		guard let passwordData = item as? Data,
			  let password = String(data: passwordData, encoding: String.Encoding.utf8) else {
			throw createApplicationError(localizedDescription: "passwordData is nil or not UTF-8 encoded.")
		}

		return password
	}

	/// force-delete local account information. Only use as a last resort!
	/*private*/ static func removePasswordFromKeychain() throws {
		let homeServer = homeServerURL.absoluteString
		let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
									kSecAttrServer as String: homeServer]
		try SecKey.check(status: SecItemDelete(query as CFDictionary), localizedError: NSLocalizedString("Deleting key from keychain failed.", comment: "Attempt to delete a keychain item failed."))
	}

	// MARK: Instance Properties and Methods

	private let session: MXSession
	private var roomsForPeerIDs = SynchronizedDictionary<PeerID, MXRoom>(queueLabel: "\(BundleID).roomsForPeerIDs")

	// as this method also invalidates the deviceId, other users cannot send us encrypted messages anymore. So we never logout except for when we delete the account.
	/// this will close the underlying session. Do not re-use it (do not make any more calls to this ServerChatController instance).
	private func logout(completion: @escaping (Error?) -> Void) {
		DispatchQueue.main.async {
			let session = self.session
			// we need to drop the instance s.t. no two logout requests are made on the same instance
			ServerChatController._instance = nil
			session.logout { response in
				if response.isFailure {
					NSLog("ERROR: Failed to log out successfully - still dropped ServerChatController.")
				}
				// *** roughly based on MXKAccount.closeSession(true) ***
				// Force a reload of device keys at the next session start.
				// This will fix potential UISIs other peoples receive for our messages.
				session.crypto?.resetDeviceKeys()
				session.scanManager?.deleteAllAntivirusScans()
				session.aggregations?.resetData()
				session.close()
				session.store?.deleteAllData()
				completion(response.error)
			}
		}
	}

	/// this will close the underlying session and invalidate the global ServerChatController instance.
	static func close() {
		DispatchQueue.main.async {
			guard let instance = _instance else { return }
			// we need to drop the instance s.t. no two logout requests are made on the same instance
			_instance = nil

			let session = instance.session
			// *** roughly based on MXKAccount.closeSession(true) ***
			// Force a reload of device keys at the next session start.
			// This will fix potential UISIs other peoples receive for our messages.
			session.crypto?.resetDeviceKeys()
			session.scanManager?.deleteAllAntivirusScans()
			session.aggregations?.resetData()
			session.close()
		}
	}

	func send(message: String, to peerID: PeerID, completion: @escaping (Result<String?, Error>) -> Void) {
		var event: MXEvent? = nil
		if let room = roomsForPeerIDs[peerID] {
			room.sendTextMessage(message, localEcho: &event) { response in
				completion(response.toResult())
			}
		} else {
			createRoom(with: peerID) { result in
				switch (result) {
				case .success(let room):
					room.sendTextMessage(message, localEcho: &event) { response in
						completion(response.toResult())
					}
				case .failure(let error):
					completion(.failure(error))
				}
			}
		}
	}

	private var notificationObservers: [Any] = []

	private init(credentials: MXCredentials) {
		let options = MXSDKOptions.sharedInstance()
		options.enableCryptoWhenStartingMXSession = true
		options.disableIdenticonUseForUserAvatar = true
		options.enableKeyBackupWhenStartingMXCrypto = false // does not work with Dendrite apparently
		let restClient = MXRestClient(credentials: credentials, unrecognizedCertificateHandler: nil)
		session = MXSession(matrixRestClient: restClient)!
		notificationObservers.append(AccountController.Notifications.unpinned.addPeerObserver { [weak self] peerID, _ in
			guard let strongSelf = self, let room = strongSelf.roomsForPeerIDs.removeValue(forKey: peerID) else { return }
			strongSelf.forget(room: room) { _error in
				NSLog("DEBUG: Left room: \(String(describing: _error)).")
			}
		})
		// mxRoomSummaryDidChange fires very often, but at some point the room contains a directUserId
		// mxRoomInitialSync does not fire that often and contains the directUserId only for the receiver. But that is okay, since the initiator of the room knows it anyway
		notificationObservers.append(NotificationCenter.default.addObserver(forName: .mxRoomInitialSync, object: nil, queue: nil) { [weak self] notification in
			guard let strongSelf = self else { return }
			for room in strongSelf.session.rooms {
				guard let userId = room.directUserId else {
					NSLog("ERROR: Found non-direct room.")
					return
				}
				guard let peerID = peerIDFrom(serverChatUserId: userId) else {
					NSLog("ERROR: Found room with non-PeerID \(userId).")
					return
				}
				self?.addRoomAndListenToEvents(room, for: peerID)
			}
		})
	}

	deinit {
		for observer in notificationObservers { NotificationCenter.default.removeObserver(observer) }
	}

	// MARK: Server Messages

	private func reallyCreateRoom(with peerID: PeerID, completion: @escaping (Result<MXRoom, Error>) -> Void) {
		let peerUserId = serverChatUserId(for: peerID)
		let roomParameters = MXRoomCreationParameters(forDirectRoomWithUser: peerUserId)
		roomParameters.visibility = kMXRoomDirectoryVisibilityPrivate
		self.session.canEnableE2EByDefaultInNewRoom(withUsers: [peerUserId]) { canEnableE2E in
			guard canEnableE2E else {
				completion(.failure(createApplicationError(localizedDescription: NSLocalizedString("End-to-end encryption is not available for this peer.", comment: "Low-level server chat error"))))
				return
			}
			roomParameters.initialStateEvents = [MXRoomCreationParameters.initialStateEventForEncryption(withAlgorithm: kMXCryptoMegolmAlgorithm)]
			self.session.createRoom(parameters: roomParameters) { response in
				guard let roomResponse = response.value else {
					completion(.failure(response.error!))
					return
				}
				guard let room = self.session.room(withRoomId: roomResponse.roomId) else {
					completion(.failure(unexpectedNilError()))
					return
				}
				self.addRoomAndListenToEvents(room, for: peerID)
				completion(.success(room))
			}
		} failure: { _error in
			completion(.failure(_error ?? unexpectedNilError()))
		}
	}

	private func createRoom(with peerID: PeerID, completion: @escaping (Result<MXRoom, Error>) -> Void) {
		let peerUserId = serverChatUserId(for: peerID)
		if let room = roomsForPeerIDs[peerID] ?? session.directJoinedRoom(withUserId: peerUserId) {
			completion(.success(room))
			return
		}

		// FUCK THIS SHIT: session.matrixRestClient.profile(forUser: peerUserId) crashes on my iPad with iOS 9.2
		if #available(iOS 10, *) {
			session.matrixRestClient.profile(forUser: peerUserId) { response in
				guard response.isSuccess else {
					DispatchQueue.main.async {
						let format = NSLocalizedString("%@ cannot chat online.", comment: "Error message when creating server chat room")
						let peerName = (PinMatchesController.shared.pinMatchedPeers.first { $0.peerID == peerID })?.nickname ?? peerID.uuidString
						let description = String(format: format, peerName)
						completion(.failure(createApplicationError(localizedDescription: description)))
					}
					return
				}
				self.reallyCreateRoom(with: peerID, completion: completion)
			}
		} else {
			reallyCreateRoom(with: peerID, completion: completion)
		}
	}

	private static func process(messageEvent event: MXEvent) -> String? {
		guard event.content["format"] == nil else {
			NSLog("ERROR: Body is formatted \(String(describing: event.content["format"])), ignoring.")
			return nil
		}
		let messageType = MXMessageType(identifier: event.content["msgtype"] as? String ?? "error_message_type_not_a_string")
		guard messageType == .text || messageType == .notice else {
			NSLog("ERROR: Unsupported message type: \(messageType).")
			return nil
		}
		guard let message = event.content["body"] as? String else {
			NSLog("ERROR: Message body not a string: \(event.content["body"] ?? "<nil>").")
			return nil
		}
		return message
	}

	private func addRoomAndListenToEvents(_ room: MXRoom, for peerID: PeerID) {
		if let oldRoom = roomsForPeerIDs[peerID] {
			NSLog("WARN: Trying to listen to already registered room \(room.roomId ?? "<no roomId>") to userID \(room.directUserId ?? "<no direct userId>").")
			guard oldRoom.roomId != room.roomId else { return }
			self.forget(room: room) { _error in
				NSLog("DEBUG: Left old room: \(String(describing: _error)).")
			}
		}
		roomsForPeerIDs[peerID] = room
		let peerManager = PeeringController.shared.manager(for: peerID)

		// replay missed messages
		let enumerator = room.enumeratorForStoredMessages
		let ourUserId = ServerChatController.userId
		// these are all messages that have been sent while we where offline
		var catchUpMissedMessages = [Transcript]()
		var encryptedEvents = [MXEvent]()
		// we cannot reserve capacity in catchUpMessages here, since enumerator.remaining may be infinite
		while let event = enumerator?.nextEvent {
			switch event.eventType {
			case .roomMessage:
				guard let message = ServerChatController.process(messageEvent: event) else { continue }
				catchUpMissedMessages.append(Transcript(direction: event.sender == ourUserId ? .send : .receive, message: message))
			case .roomEncrypted:
				encryptedEvents.append(event)
			default:
				break
			}
		}
		catchUpMissedMessages.reverse()

		room.liveTimeline { _timeline in
			guard let timeline = _timeline else {
				NSLog("ERROR: No timeline retrieved.")
				return
			}

			// we need to reset the replay attack check, as we kept getting errors like:
			// [MXOlmDevice] decryptGroupMessage: Warning: Possible replay attack
			self.session.resetReplayAttackCheck(inTimeline: timeline.timelineId)
			self.session.decryptEvents(encryptedEvents, inTimeline: timeline.timelineId) { _failedEvents in
				if let failedEvents = _failedEvents, failedEvents.count > 0 {
					for failedEvent in failedEvents {
						NSLog("WARN: Couldn't decrypt event: \(failedEvent.eventId ?? "<nil>"). Reason: \(failedEvent.decryptionError ?? unexpectedNilError())")
					}
				}

				// these are all messages that we have seen earlier already, but we need to decryt them again apparently
				var catchUpDecryptedMessages = [Transcript]()
				for event in encryptedEvents {
					switch event.eventType {
					case .roomMessage:
						guard let message = ServerChatController.process(messageEvent: event) else { continue }
						catchUpDecryptedMessages.append(Transcript(direction: event.sender == ourUserId ? .send : .receive, message: message))
					default:
						break
					}
				}
				catchUpDecryptedMessages.reverse()
				catchUpDecryptedMessages.append(contentsOf: catchUpMissedMessages)
				if catchUpDecryptedMessages.count > 0 { peerManager.catchUp(messages: catchUpDecryptedMessages) }
			}

			_ = timeline.listenToEvents([.roomMessage]) { event, direction, state in
				switch event.eventType {
				case .roomMessage:
					guard let message = ServerChatController.process(messageEvent: event) else { return }
					if event.sender == ServerChatController.userId {
						peerManager.didSend(message: message)
					} else {
						peerManager.received(message: message)
					}
				default:
					NSLog("WARN: Received event we didn't listen for: \(event.type ?? "<unknown event type>").")
				}
			}
		}
	}

	private func start(completion: @escaping (Error?) -> Void) {
		let store = MXFileStore(credentials: session.credentials) // MXMemoryStore()
		session.setStore(store) { setStoreResponse in
			guard setStoreResponse.isSuccess else {
				completion(setStoreResponse.error ?? unexpectedNilError())
				return
			}
			// as we do everything in the background and the deviceId's are re-generated every time, verifying each device does not give enough benefit here
			self.session.crypto?.warnOnUnknowDevices = false
			// TODO: sync only back to last went offline
			let filter = MXFilterJSONModel.syncFilter(withMessageLimit: 10)!
			self.session.start(withSyncFilter: filter) { response in
				guard response.isSuccess else {
					completion(response.error ?? unexpectedNilError())
					return
				}
				for room in self.session.rooms {
					guard let userId = room.directUserId else {
						NSLog("ERROR: Room \(room.roomId ?? "<unknown>") is either not direct or the userId is not loaded.")
						continue
					}
					guard let peerID = peerIDFrom(serverChatUserId: userId) else {
						NSLog("ERROR: Server chat userId \(userId) is not a PeerID.")
						continue
					}
					self.addRoomAndListenToEvents(room, for: peerID)
				}

				_ = self.session.listenToEvents { event, direction, customObject in
					NSLog("DEBUG: global event \(event), \(direction), \(String(describing: customObject))")
				}
				_ = self.session.listenToEvents([.roomMember]) { event, direction, state in
					switch event.eventType {
					case .roomMember:
						guard let memberContent = MXRoomMemberEventContent(fromJSON: event.content) else {
							NSLog("ERROR: Cannot construct MXRoomCreateContent from event content.")
							return
						}
						guard let userId = event.stateKey else {
							// we are only interested in joins from other people
							NSLog("ERROR: No stateKey present in membership event.")
							return
						}
						switch memberContent.membership {
						case kMXMembershipStringJoin:
							// we handle joins through the mxRoomInitialSync notification
							break
						case kMXMembershipStringInvite:
							guard userId == ServerChatController.userId else {
								// we are only interested in invites for us
								NSLog("INFO: Received invite event from sender other than us.")
								return
							}
							self.session.joinRoom(event.roomId) { joinResponse in
								guard joinResponse.isSuccess else {
									NSLog("ERROR: Cannot join room \(event.roomId ?? "<nil>"): \(joinResponse.error ?? unexpectedNilError())")
									return
								}
								// we do not addRoomAndListenToEvents here, since we do it in the mxRoomInitialSync notification
							}
						case kMXMembershipStringLeave:
							guard userId != ServerChatController.userId else {
								// we are only interested in leaves from other people
								NSLog("DEBUG: Received our leave event.")
								return
							}
							guard let room = self.session.room(withRoomId: event.roomId) else {
								NSLog("ERROR: No such room: \(event.roomId ?? "<nil>").")
								return
							}
							// I hope this suspends the event stream as well…
							self.forget(room: room) { _error in
								NSLog("DEBUG: Left empty room: \(String(describing: _error)).")
							}
							guard let peerID = peerIDFrom(serverChatUserId: userId) else {
								NSLog("ERROR: cannot construct PeerID from room directUserId \(userId).")
								return
							}
							_ = self.roomsForPeerIDs.removeValue(forKey: peerID)
							guard let peerInfo = PinMatchesController.shared.peerInfo(for: peerID) else {
								NSLog("WARN: No peer info for peer ID available from pin matches controller.")
								return
							}
							AccountController.shared.updatePinStatus(of: peerInfo)
						default:
							NSLog("WARN: Unexpected room membership \(memberContent.membership ?? "<nil>").")
						}
					default:
						NSLog("WARN: Received global event we didn't listen for: \(event.type ?? "<unknown event type>").")
						break
					}
				}
				completion(response.error)
			}
		}
	}
}

extension MXResponse {
	/// Result removes the dependency to MatrixSDK, resulting in only this file (ServerChatController.swift) depending on it
	func toResult() -> Result<T, Error> {
		switch self {
		case .failure(let error):
			return .failure(error)
		case .success(let value):
			return .success(value)
		@unknown default:
			return .failure(unexpectedEnumValueError())
		}
	}
}
