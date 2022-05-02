//
//  ServerChatController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 12.05.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import Foundation
import MatrixSDK

/// Internal implementaion of the `ServerChat` protocol.
final class ServerChatController: ServerChat {
	// MARK: - Public and Internal

	/// Creates a `ServerChatController`.
	init(peerID: PeerID, credentials: MXCredentials, dQueue: DispatchQueue) {
		self.peerID = peerID
		self.dQueue = dQueue

		let restClient = MXRestClient(credentials: credentials, unrecognizedCertificateHandler: nil)
		restClient.completionQueue = dQueue
		session = MXSession(matrixRestClient: restClient)!
	}

	// MARK: Variables

	var delegate: ServerChatDelegate? = nil

	// MARK: Methods

	/// this will close the underlying session and invalidate the global ServerChatController instance.
	func close() {
		for observer in notificationObservers { NotificationCenter.default.removeObserver(observer) }
		notificationObservers.removeAll()

		// *** roughly based on MXKAccount.closeSession(true) ***
		// Force a reload of device keys at the next session start.
		// This will fix potential UISIs other peoples receive for our messages.
		session.crypto?.resetDeviceKeys()
		session.scanManager?.deleteAllAntivirusScans()
		session.aggregations?.resetData()
		session.close()
	}

	// as this method also invalidates the deviceId, other users cannot send us encrypted messages anymore. So we never logout except for when we delete the account.
	/// this will close the underlying session. Do not re-use it (do not make any more calls to this ServerChatController instance).
	func logout(_ completion: @escaping (Error?) -> Void) {
		self.session.extensiveLogout(completion)
	}

	// MARK: ServerChat

	/// Send a `message` to `peerID`.
	func send(message: String, to peerID: PeerID, _ completion: @escaping (Result<String?, Error>) -> Void) {
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

	/// Set up APNs.
	func configurePusher(deviceToken: Data) {
		guard let mx = session.matrixRestClient else { return }

		let b64Token = deviceToken.base64EncodedString()
		let pushData: [String : Any] = [
			"url": "http://pushgateway/_matrix/push/v1/notify",
			"format": "event_id_only",
			"default_payload": [
				"aps": [
//					"mutable-content": 1,
					"alert": [
						"loc-key": "MSG_FROM_USER",
						"loc-args": []
					]
				]
			]
		]
		let language = Locale.preferredLanguages.first ?? "en"

#if DEBUG
		let appID = "de.peeree.ios.dev"
#else
		let appID = "de.peeree.ios.prod"
#endif

		let displayName = "Peeree iOS"

		var profileTag = UserDefaults.standard.string(forKey: Self.ProfileTagKey) ?? ""
		if profileTag.count < 16 {
			profileTag = Self.ProfileTagAllowedChars.shuffled().reduce("") { partialResult, c in
				guard partialResult.count < 16 else { return partialResult }
				return partialResult.appending("\(c)")
			}
			UserDefaults.standard.set(profileTag, forKey: Self.ProfileTagKey)
		}

		mx.setPusher(pushKey: b64Token, kind: .http, appId: appID, appDisplayName: displayName, deviceDisplayName: userId, profileTag: profileTag, lang: language, data: pushData, append: false) { response in
			switch response.toResult() {
			case .failure(let error):
				elog("setPusher() failed: \(error)")
				self.delegate?.configurePusherFailed(error)
			case .success():
				dlog("setPusher() was successful.")
			}
		}
	}

	// MARK: - Private

	// MARK: Static Constants

	/// Used for APNs.
	private static let ProfileTagAllowedChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

	/// Matrix pusher profile tag key in `UserDefaults`.
	private static let ProfileTagKey = "ServerChatController.profileTag"

	// MARK: Constants

	/// The PeerID of the user.
	private let peerID: PeerID

	/// Target for matrix operations.
	private let dQueue: DispatchQueue

	/// Matrix session.
	private let session: MXSession

	// MARK: Variables

	/// Lookup for matrix direct rooms.
	private var roomsForPeerIDs = SynchronizedDictionary<PeerID, MXRoom>(queueLabel: "\(BundleID).roomsForPeerIDs")

	/// Matrix userId based on user's PeerID.
	private var userId: String { return serverChatUserId(for: peerID) }

	/// All references to NotificationCenter observers by this object.
	private var notificationObservers: [Any] = []

	// MARK: Methods

	/// Create a direct room for chatting with `peerID`.
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

	/// Create a direct room for chatting with `peerID`.
	private func createRoom(with peerID: PeerID, completion: @escaping (Result<MXRoom, Error>) -> Void) {
		dlog("Asked to create room for \(peerID.uuidString).")
		let peerUserId = serverChatUserId(for: peerID)
		if let room = roomsForPeerIDs[peerID] ?? session.directJoinedRoom(withUserId: peerUserId) {
			completion(.success(room))
			return
		}

		// FUCK THIS SHIT: session.matrixRestClient.profile(forUser: peerUserId) crashes on my iPad with iOS 9.2
		if #available(iOS 10, *) {
			session.matrixRestClient.profile(forUser: peerUserId) { response in
				guard response.isSuccess else {
					let format = NSLocalizedString("%@ cannot chat online.", comment: "Error message when creating server chat room")
					let description = String(format: format, peerID.uuidString)
					completion(.failure(createApplicationError(localizedDescription: description)))
					return
				}
				self.reallyCreateRoom(with: peerID, completion: completion)
			}
		} else {
			reallyCreateRoom(with: peerID, completion: completion)
		}
	}

	/// Listens to events in `room`.
	private func addRoomAndListenToEvents(_ room: MXRoom, for peerID: PeerID) {
		if let oldRoom = roomsForPeerIDs[peerID] {
			wlog("Trying to listen to already registered room \(room.roomId ?? "<no roomId>") to userID \(room.directUserId ?? "<no direct userId>").")
			guard oldRoom.roomId != room.roomId else {
				wlog("Tried to add already known room \(room.roomId ?? "<unknown room id>").")
				return
			}
			self.forget(room: oldRoom) { _error in
				dlog("Left old room: \(String(describing: _error)).")
			}
		}
		roomsForPeerIDs[peerID] = room

		PeeringController.shared.getLastReads { lastReads in

		// replay missed messages
		let enumerator = room.enumeratorForStoredMessages
		let ourUserId = self.userId
		let lastReadDate = lastReads[peerID] ?? Date.distantFuture

		// these are all messages that have been sent while we where offline
		var catchUpMissedMessages = [Transcript]()
		var encryptedEvents = [MXEvent]()
		var unreadMessages = 0

		// we cannot reserve capacity in catchUpMessages here, since enumerator.remaining may be infinite
		while let event = enumerator?.nextEvent {
			switch event.eventType {
			case .roomMessage:
				do {
					let messageEvent = try MessageEventData(messageEvent: event)
					catchUpMissedMessages.append(Transcript(direction: event.sender == ourUserId ? .send : .receive, message: messageEvent.message, timestamp: messageEvent.timestamp))
					if messageEvent.timestamp > lastReadDate { unreadMessages += 1 }
				} catch let error {
					elog("\(error)")
				}
			case .roomEncrypted:
				encryptedEvents.append(event)
			default:
				break
			}
		}
		catchUpMissedMessages.reverse()

		room.liveTimeline { _timeline in
			guard let timeline = _timeline else {
				elog("No timeline retrieved.")
				return
			}

			// we need to reset the replay attack check, as we kept getting errors like:
			// [MXOlmDevice] decryptGroupMessage: Warning: Possible replay attack
			self.session.resetReplayAttackCheck(inTimeline: timeline.timelineId)

#if os(iOS)
			// decryptEvents() is somehow not available on macOS
			self.session.decryptEvents(encryptedEvents, inTimeline: timeline.timelineId) { _failedEvents in
				if let failedEvents = _failedEvents, failedEvents.count > 0 {
					for failedEvent in failedEvents {
						wlog("Couldn't decrypt event: \(failedEvent.eventId ?? "<nil>"). Reason: \(failedEvent.decryptionError ?? unexpectedNilError())")
					}
				}

				// these are all messages that we have seen earlier already, but we need to decryt them again apparently
				var catchUpDecryptedMessages = [Transcript]()
				for event in encryptedEvents {
					switch event.eventType {
					case .roomMessage:
						do {
							let messageEvent = try MessageEventData(messageEvent: event)
							catchUpDecryptedMessages.append(Transcript(direction: event.sender == ourUserId ? .send : .receive, message: messageEvent.message, timestamp: messageEvent.timestamp))
							if messageEvent.timestamp > lastReadDate { unreadMessages += 1 }
						} catch let error {
							elog("\(error)")
						}
					default:
						break
					}
				}
				catchUpDecryptedMessages.reverse()
				catchUpDecryptedMessages.append(contentsOf: catchUpMissedMessages)
				if catchUpDecryptedMessages.count > 0 {
					PeeringController.shared.serverChatInteraction(with: peerID) { manager in
						manager.catchUp(messages: catchUpDecryptedMessages, unreadCount: unreadMessages)
					}
				}
			}
#endif

			_ = timeline.listenToEvents([.roomMessage]) { event, direction, state in
				switch event.eventType {
				case .roomMessage:
					do {
						let messageEvent = try MessageEventData(messageEvent: event)

						PeeringController.shared.serverChatInteraction(with: peerID) { manager in
							if event.sender == ourUserId {
								manager.didSend(message: messageEvent.message, at: messageEvent.timestamp)
							} else {
								manager.received(message: messageEvent.message, at: messageEvent.timestamp)
							}
						}
					} catch let error {
						elog("\(error)")
					}
				default:
					wlog("Received event we didn't listen for: \(event.type ?? "<unknown event type>").")
				}
			}
		}
		}
	}

	/// Tries to leave (and forget [once supported]) <code>room</code>, ignoring any errors
	private func forget(room: MXRoom, completion: @escaping (Error?) -> Void) {
		room.leave { response in
			// TODO implement [forget](https://matrix.org/docs/spec/client_server/r0.6.1#id294) API call once it is available in matrix-ios-sdk
			completion(response.error)
		}
	}

	/// Tries to leave (and forget [once supported]) <code>rooms</code>, ignoring any errors
	private func forget(rooms: [MXRoom], completion: @escaping () -> Void) {
		var leftoverRooms = rooms // inefficient as hell: always creates a whole copy of the array
		guard let room = leftoverRooms.popLast() else {
			completion()
			return
		}
		room.leave { response in
			if let error = response.error {
				elog("Failed leaving room: \(error.localizedDescription)")
			}
			// TODO implement [forget](https://matrix.org/docs/spec/client_server/r0.6.1#id294) API call once it is available in matrix-ios-sdk
			self.forget(rooms: leftoverRooms, completion: completion)
		}
	}

	/// Handles room member events.
	private func process(memberEvent event: MXEvent) {
		switch event.eventType {
		case .roomMember:
			guard let memberContent = MXRoomMemberEventContent(fromJSON: event.content) else {
				elog("Cannot construct MXRoomCreateContent from event content.")
				return
			}
			guard let eventUserId = event.stateKey else {
				// we are only interested in joins from other people
				elog("No stateKey present in membership event.")
				return
			}

			switch memberContent.membership {
			case kMXMembershipStringJoin:
				// we handle joins through the mxRoomInitialSync notification
				break

			case kMXMembershipStringInvite:
				guard eventUserId == self.userId else {
					// we are only interested in invites for us
					ilog("Received invite event from sender other than us.")
					return
				}
				self.session.joinRoom(event.roomId) { joinResponse in
					guard joinResponse.isSuccess else {
						elog("Cannot join room \(event.roomId ?? "<nil>"): \(joinResponse.error ?? unexpectedNilError())")
						return
					}
					// we do not addRoomAndListenToEvents here, since we do it in the mxRoomInitialSync notification
				}

				// check whether we actually have a pin match with this person
				guard let peerID = peerIDFrom(serverChatUserId: event.sender) else {
					elog("Cannot construct PeerID from userId \(event.sender ?? "<nil>").")
					return
				}

				AccountController.use { ac in
					guard !ac.hasPinMatch(peerID) else { return }
					ac.updatePinStatus(of: peerID, force: true)
				}

			case kMXMembershipStringLeave:
				guard eventUserId != self.userId else {
					// we are only interested in leaves from other people
					dlog("Received our leave event.")
					return
				}
				guard let room = self.session.room(withRoomId: event.roomId) else {
					elog("No such room: \(event.roomId ?? "<nil>").")
					return
				}

				// I hope this suspends the event stream as well…
				self.forget(room: room) { _error in
					dlog("Left empty room: \(String(describing: _error)).")
				}

				guard let peerID = peerIDFrom(serverChatUserId: userId) else {
					elog("cannot construct PeerID from room directUserId \(userId).")
					return
				}

				_ = self.roomsForPeerIDs.removeValue(forKey: peerID)

				// check whether we still have a pin match with this person
				AccountController.use { ac in
					ac.updatePinStatus(of: peerID, force: true)
				}

			default:
				wlog("Unexpected room membership \(memberContent.membership ?? "<nil>").")
			}
		default:
			wlog("Received global event we didn't listen for: \(event.type ?? "<unknown event type>").")
			break
		}
	}

	/// Begin the session.
	func start(_ completion: @escaping (Error?) -> Void) {
		observeNotifications()

		let store = MXFileStore(credentials: session.credentials) // MXMemoryStore()
		session.setStore(store) { setStoreResponse in
			guard setStoreResponse.isSuccess else {
				completion(setStoreResponse.error ?? unexpectedNilError())
				return
			}
			// as we do everything in the background, verifying each device does not give enough benefit here
			self.session.crypto?.warnOnUnknowDevices = false

			let filter = MXFilterJSONModel.syncFilter(withMessageLimit: 10)!
			self.session.start(withSyncFilter: filter) { response in
				guard response.isSuccess else {
					completion(response.error ?? unexpectedNilError())
					return
				}
				for room in self.session.rooms {
					guard let userId = room.directUserId else {
						elog("Room \(room.roomId ?? "<unknown>") is either not direct or the userId is not loaded.")
						continue
					}
					guard let peerID = peerIDFrom(serverChatUserId: userId) else {
						elog("Server chat userId \(userId) is not a PeerID.")
						continue
					}
					self.addRoomAndListenToEvents(room, for: peerID)
				}

//				_ = self.session.listenToEvents { event, direction, customObject in
//					dlog("global event \(event), \(direction), \(String(describing: customObject))")
//				}
				_ = self.session.listenToEvents([.roomMember]) { event, direction, state in
					self.process(memberEvent: event)
				}
				completion(response.error)
			}
		}
	}

	/// Observes relevant notifications in `NotificationCenter`.
	private func observeNotifications() {
		notificationObservers.append(AccountController.NotificationName.unpinned.addAnyPeerObserver { [weak self] peerID, _ in
			guard let strongSelf = self, let room = strongSelf.roomsForPeerIDs.removeValue(forKey: peerID) else { return }

			// we don't need to use dQueue here, since forget is not mutating.
			strongSelf.forget(room: room) { _error in
				dlog("Left room: \(String(describing: _error)).")
			}
		})

		// mxRoomSummaryDidChange fires very often, but at some point the room contains a directUserId
		// mxRoomInitialSync does not fire that often and contains the directUserId only for the receiver. But that is okay, since the initiator of the room knows it anyway
		notificationObservers.append(NotificationCenter.default.addObserver(forName: .mxRoomInitialSync, object: nil, queue: nil) { [weak self] notification in
			guard let strongSelf = self else { return }

			for room in strongSelf.session.rooms {
				guard let userId = room.directUserId else {
					elog("Found non-direct room \(room.roomId ?? "<nil>").")
					return
				}
				guard let peerID = peerIDFrom(serverChatUserId: userId) else {
					elog("Found room with non-PeerID \(userId).")
					return
				}

				strongSelf.addRoomAndListenToEvents(room, for: peerID)
			}
		})
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

extension MXSession {
	/// Logs outs the session as well as cleans up more local stuff.
	func extensiveLogout(_ completion: @escaping (Error?) -> ()) {
		logout { response in
			if response.isFailure {
				elog("Failed to log out successfully - still cleaning up session data.")
			}
			// *** roughly based on MXKAccount.closeSession(true) ***
			// Force a reload of device keys at the next session start.
			// This will fix potential UISIs other peoples receive for our messages.
			self.crypto?.resetDeviceKeys()
			self.scanManager?.deleteAllAntivirusScans()
			self.aggregations?.resetData()
			self.close()
			self.store?.deleteAllData()
			completion(response.error)
		}
	}
}
