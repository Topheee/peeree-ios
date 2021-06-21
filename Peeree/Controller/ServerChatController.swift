//
//  ServerChatController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 12.05.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import Foundation
import MatrixSDK

public typealias RoomID = String
public typealias UserID = String

let serverChatDomain = "chat.peeree.de"

func serverChatUserId(for peerID: PeerID) -> String {
	return "@\(serverChatUserName(for: peerID)):\(serverChatDomain)"
}

func peerIDFrom(serverChatUserId userId: UserID) -> PeerID? {
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
	static let userId = serverChatUserId(for: UserPeerManager.instance.peerID)
	// we need to keep a strong reference to the client s.t. it is not destroyed while requests are in flight
	static let globalRestClient = MXRestClient(homeServer: homeServerURL) { _data in
		NSLog("ERROR: matrix certificate rejected: \(String(describing: _data))")
		return false
	}

	// MARK: Singleton Lifecycle

	/// access only from main thread!
	private static var _instance: ServerChatController? = nil

	static func withInstance(getter: @escaping (ServerChatController?) -> Void) {
		DispatchQueue.main.async { getter(_instance) }
	}

	static func getOrSetupInstance(onlyLogin: Bool = false, completion: @escaping (Result<ServerChatController, Error>) -> Void) {
		DispatchQueue.main.async {
			if let instance = _instance {
				completion(.success(instance))
				return
			}

			login { loginResult in
				switch loginResult {
				case .success(let credentials):
					setupInstance(with: credentials, completion: completion)
				case .failure(let error):
					guard !onlyLogin else {
						completion(.failure(error))
						return
					}
					NSLog("WARN: server chat login failed: \(error.localizedDescription)")
					createAccount { createAccountResult in
						switch createAccountResult {
						case .success(let credentials):
							setupInstance(with: credentials, completion: completion)
						case .failure(let error):
							completion(.failure(error))
						}
					}
				}
			}
		}
	}

	private static func setupInstance(with credentials: MXCredentials, completion: @escaping (Result<ServerChatController, Error>) -> Void) {
		let c = ServerChatController(credentials: credentials)
		_instance = c
		c.start { _error in
			if let error = _error {
				completion(.failure(error))
			} else {
				completion(.success(c))
			}
		}
	}

	private static func createAccount(completion: @escaping (Result<MXCredentials, Error>) -> Void) {
		let peerID = UserPeerManager.instance.peerID
		let username = serverChatUserName(for: peerID)
		let passwordRawData: Data
		do {
			passwordRawData = try generateRandomData(length: Int.random(in: 24...26))
		} catch let error {
			completion(.failure(error))
			return
		}
		let passwordData = passwordRawData.base64EncodedData()
		if String(data: passwordData, encoding: .utf8) != passwordRawData.base64EncodedString() {
			NSLog("UH-OH")
		}
		do {
			try persistPasswordInKeychain(passwordData)
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
	}

	private static func login(completion: @escaping (Result<MXCredentials, Error>) -> Void) {
		let password: String
		do {
			password = try passwordFromKeychain()
		} catch let error {
			completion(.failure(error))
			return
		}
		globalRestClient.login(type: .password, username: userId, password: password) { response in
			if let error = response.error as NSError? {
				if let mxErrCode = error.userInfo[kMXErrorCodeKey] as? String {
					if mxErrCode == "M_INVALID_USERNAME" {
						NSLog("ERROR: Our account seems to be deleted. Removing local password for re-registering.")
						do {
							try ServerChatController.removePasswordFromKeychain()
						} catch let pwError {
							NSLog("WARN: Removing local password failed, not an issue if not existant: \(pwError.localizedDescription)")
						}
					}
				}
			}
			completion(response.toResult())
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
		session.deactivateAccount(withAuthParameters: ["type" : kMXLoginFlowTypePassword, "user" : ServerChatController.userId, "password" : password], eraseAccount: true) { response in
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
	private var roomsForPeerIDs = [PeerID : MXRoom]()

	func logout(completion: @escaping (Error?) -> Void) {
		DispatchQueue.main.async {
			// we need to drop the instance s.t. no two logout requests are made on the same instance
			ServerChatController._instance = nil
			self.session.logout { response in
				if response.isFailure {
					NSLog("ERROR: Failed to log out successfully - still dropped ServerChatController.")
				}
				completion(response.error)
			}
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
		MXSDKOptions.sharedInstance().enableCryptoWhenStartingMXSession = false
		let restClient = MXRestClient(credentials: credentials, unrecognizedCertificateHandler: nil)
		session = MXSession(matrixRestClient: restClient)!
		notificationObservers.append(AccountController.Notifications.unpinned.addPeerObserver { [weak self] peerID, _ in
			guard let strongSelf = self, let room = strongSelf.roomsForPeerIDs.removeValue(forKey: peerID) else { return }
			room.leave { leaveRoomResponse in
				NSLog("DEBUG: Left room: \(leaveRoomResponse).")
			}
		})
		notificationObservers.append(NotificationCenter.default.addObserver(forName: .mxRoomSummaryDidChange, object: nil, queue: nil) { [weak self] notification in
			// THIS IS MORE THAN STUPID: we would just need to get notified after the initial sync?! or when the room is added?! But NO!
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

	private func createRoom(with peerID: PeerID, completion: @escaping (Result<MXRoom, Error>) -> Void) {
		let peerUserId = serverChatUserId(for: peerID)
		let roomParameters = MXRoomCreationParameters(forDirectRoomWithUser: peerUserId)
		roomParameters.visibility = kMXRoomDirectoryVisibilityPrivate
		if let room = session.directJoinedRoom(withUserId: peerUserId) {
			completion(.success(room))
		} else {
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
				}
			} else {
				self.session.createRoom(parameters: roomParameters) { response in
					guard let roomResponse = response.value else {
						completion(.failure(response.error!))
						return
					}
					guard let room = self.session.room(withRoomId: roomResponse.roomId) else {
						completion(.failure(unexpectedNilError()))
						return
					}
					self.addRoomAndListenToEvents(room, for: peerID) // we probably do this twice -> we cannot delete this here, since we need it to send the message to the room
					completion(.success(room))
				}
			}
		}
	}

	private func addRoomAndListenToEvents(_ room: MXRoom, for peerID: PeerID) {
		if let oldRoom = roomsForPeerIDs[peerID] {
			NSLog("WARN: Trying to listen to already registered room \(room.roomId ?? "<no roomId>") to userID \(room.directUserId ?? "<no direct userId>").")
			guard oldRoom.roomId != room.roomId else { return }
			oldRoom.leave { leaveRoomResponse in
				NSLog("DEBUG: Left old room: \(leaveRoomResponse).")
			}
		}
		roomsForPeerIDs[peerID] = room
		room.liveTimeline { _timeline in
			guard let timeline = _timeline else {
				NSLog("ERROR: No timeline retrieved.")
				return
			}

			let peerManager = PeeringController.shared.manager(for: peerID)
			_ = timeline.listenToEvents([.roomEncrypted, .roomEncryption, .roomMessage]) { event, direction, state in
				switch event.eventType {
				case .roomEncrypted:
					// @TODO handle encryption
					break
				case .roomEncryption:
					// @TODO handle encryption
					break
				case .roomMessage:
					guard event.content["format"] as? String != kMXRoomMessageFormatHTML else {
						NSLog("ERROR: Body is HTML, ignoring.")
						return
					}
					let messageType = MXMessageType(identifier: event.content["msgtype"] as? String ?? "error_message_type_not_a_string")
					guard messageType == .text || messageType == .notice else {
						NSLog("ERROR: Unsupported message type: \(messageType).")
						return
					}
					guard let message = event.content["body"] as? String else {
						NSLog("ERROR: Message body not a string: \(event.content["body"] ?? "<nil>").")
						return
					}
					if event.sender == ServerChatController.userId {
						peerManager.didSend(message: message)
					} else {
						peerManager.received(message: message)
					}
					break
				default:
					NSLog("WARN: Received event we didn't listen for: \(event.type ?? "<unknown event type>").")
				}
				switch direction {
				case .forwards:
					// Live/New events come here
					break
				case .backwards:
					// Events that occurred in the past will come here when requesting pagination.
					// roomState contains the state of the room just before this event occurred.
					break
				@unknown default:
					NSLog("ERROR: Event with unknown direction \(direction).")
				}
			}
		}
	}

	private func start(completion: @escaping (Error?) -> Void) {
		//let store = MXNoStore()
		let store = MXMemoryStore()
		session.setStore(store) { setStoreResponse in
			guard setStoreResponse.isSuccess else {
				completion(setStoreResponse.error ?? unexpectedNilError())
				return
			}
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

				self.session.listenToEvents { event, direction, customObject in
					NSLog("DEBUG: global event \(event), \(direction), \(String(describing: customObject))")
				}
				_ = self.session.listenToEvents([.roomMember]) { event, direction, state in
					switch event.eventType {
					case .roomMember:
						guard let memberContent = MXRoomMemberEventContent(fromJSON: event.content) else {
							NSLog("ERROR: Cannot construct MXRoomCreateContent from event content.")
							return
						}
						switch memberContent.membership {
						case kMXMembershipStringJoin:
							guard let userId = event.stateKey, userId != ServerChatController.userId else {
								// we are only interested in joins from other people
								NSLog("WARN: Received our join event.")
								return
							}
							guard let room = self.session.room(withRoomId: event.roomId) else {
								NSLog("ERROR: No such room: \(event.roomId ?? "<nil>").")
								return
							}
							guard let peerID = peerIDFrom(serverChatUserId: userId) else {
								NSLog("ERROR: cannot construct PeerID from room directUserId \(userId).")
								return
							}
							self.addRoomAndListenToEvents(room, for: peerID)
						case kMXMembershipStringInvite:
							guard event.stateKey == ServerChatController.userId else {
								// we are only interested in invites for us
								NSLog("WARN: Received invite event from sender other than us.")
								return
							}
							self.session.joinRoom(event.roomId) { joinResponse in
								guard joinResponse.isSuccess else {
									NSLog("ERROR: Cannot join room \(event.roomId ?? "<nil>"): \(joinResponse.error ?? unexpectedNilError())")
									return
								}
								guard let room = self.session.room(withRoomId: event.roomId) else {
									NSLog("ERROR: No such room: \(event.roomId ?? "<nil>").")
									return
								}
								guard let userId = room.directUserId else {
									NSLog("ERROR: No direct userId in room \(room.roomId ?? "<nil>").")
									return
								}
								guard let peerID = peerIDFrom(serverChatUserId: userId) else {
									NSLog("ERROR: cannot construct PeerID from room directUserId \(userId).")
									return
								}
								self.addRoomAndListenToEvents(room, for: peerID)
							}
						case kMXMembershipStringLeave:
							// ignored
							break
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
