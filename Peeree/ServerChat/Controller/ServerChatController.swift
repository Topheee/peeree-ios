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
	init(peerID: PeerID, credentials: MXCredentials, dQueue: DispatchQueue, _ persistCredentialsCallback: @escaping () -> Void) {
		self.peerID = peerID
		self.dQueue = dQueue

		let restClient = MXRestClient(credentials: credentials) { data in
			flog("server chat certificate is not trusted.")
			return false
		} persistentTokenDataHandler: { callback in
			dlog("server chat persistentTokenDataHandler was called.")
			// Block called when the rest client needs to check the persisted refresh token data is valid and optionally persist new refresh data to disk if it is not.
			callback?([credentials]) { shouldPersist in
				// credentials (access and refresh token) changed during refresh
				if shouldPersist { persistCredentialsCallback() }
			}
		} unauthenticatedHandler: { mxError, isSoftLogout, isRefreshTokenAuth, completion in
			dlog("server chat unauthenticatedHandler was called.")
			// Block called when the rest client has become unauthenticated(E.g. refresh failed or server invalidated an access token).
			// TODO handle dis
			if let error = mxError {
				flog("server chat session became unauthenticated (soft logout: \(isSoftLogout), refresh token: \(isRefreshTokenAuth)) \(error.errcode ?? "<nil>"): \(error.error ?? "<nil>")")
			} else {
				flog("server chat session became unauthenticated (soft logout: \(isSoftLogout), refresh token: \(isRefreshTokenAuth))")
			}
		}

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

	/// Removes the server chat account permanently.
	func deleteAccount(password: String, _ completion: @escaping (ServerChatError?) -> Void) {
		session.deactivateAccount(withAuthParameters: ["type" : kMXLoginFlowTypePassword, "user" : self.userId, "password" : password], eraseAccount: true) { response in
			guard response.isSuccess else { completion(.sdk(response.error ?? unexpectedNilError())); return }

			// it seems we need to log out after we deleted the account
			self.logout { _error in
				_error.map { elog("Logout after account deletion failed: \($0.localizedDescription)") }
				// do not escalate the error of the logout, as it doesn't mean we didn't successfully deactivated the account
				completion(nil)
			}
		}
	}

	// MARK: ServerChat

	/// Checks whether `peerID` can receive or messages.
	func canChat(with peerID: PeerID, _ completion: @escaping (ServerChatError?) -> Void) {
		self.createRoom(with: peerID) { result in
			switch (result) {
			case .success(let room):
				room.members { response in
					guard let roomMembers = response.value else {
						self.handle(response: response, in: room, with: peerID) { recoverResult in
							completion(recoverResult.error)
						}
						return
					}
					guard let joinedMembers = roomMembers?.joinedMembers else {
						completion(.fatal(unexpectedNilError()))
						return
					}

					let peerUserId = serverChatUserId(for: peerID)
					if joinedMembers.contains(where: { $0.userId == peerUserId }) {
						completion(nil)
					} else {
						completion(.cannotChat(peerID, .notJoined))
					}
				}
			case .failure(let error):
				completion(error)
			}
		}
	}

	/// Send a `message` to `peerID`.
	func send(message: String, to peerID: PeerID, _ completion: @escaping (Result<String?, ServerChatError>) -> Void) {
		createRoom(with: peerID) { result in
			switch (result) {
			case .success(let room):
				var event: MXEvent? = nil
				room.sendTextMessage(message, localEcho: &event) { response in
					self.handle(response: response, in: room, with: peerID, completion)
				}
			case .failure(let error):
				completion(.failure(error))
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
	private func reallyCreateRoom(with peerID: PeerID, completion: @escaping (Result<MXRoom, ServerChatError>) -> Void) {
		let peerUserId = serverChatUserId(for: peerID)
		let roomParameters = MXRoomCreationParameters(forDirectRoomWithUser: peerUserId)
		roomParameters.visibility = kMXRoomDirectoryVisibilityPrivate
		self.session.canEnableE2EByDefaultInNewRoom(withUsers: [peerUserId]) { canEnableE2E in
			guard canEnableE2E else {
				completion(.failure(.cannotChat(peerID, .noEncryption)))
				return
			}
			roomParameters.initialStateEvents = [MXRoomCreationParameters.initialStateEventForEncryption(withAlgorithm: kMXCryptoMegolmAlgorithm)]
			self.session.createRoom(parameters: roomParameters) { response in
				guard let roomResponse = response.value else {
					completion(.failure(.sdk(response.error ?? unexpectedNilError())))
					return
				}
				guard let room = self.session.room(withRoomId: roomResponse.roomId) else {
					completion(.failure(.fatal(unexpectedNilError())))
					return
				}
				self.addRoomAndListenToEvents(room, for: peerID)
				completion(.success(room))
			}
		} failure: { error in
			completion(.failure(.sdk(error ?? unexpectedNilError())))
		}
	}

	/// Create a direct room for chatting with `peerID`.
	private func createRoom(with peerID: PeerID, completion: @escaping (Result<MXRoom, ServerChatError>) -> Void) {
		dlog("Asked to create room for \(peerID.uuidString).")
		let peerUserId = serverChatUserId(for: peerID)
		// unfortunately, directJoinedRoom returns a room we are not joined anymore in some cases
		if let room = roomsForPeerIDs[peerID] /*?? session.directJoinedRoom(withUserId: peerUserId) */ {
			completion(.success(room))
			return
		}

		// FUCK THIS SHIT: session.matrixRestClient.profile(forUser: peerUserId) crashes on my iPad with iOS 9.2
		if #available(iOS 10, *) {
			session.matrixRestClient.profile(forUser: peerUserId) { response in
				guard response.isSuccess else {
					completion(.failure(.cannotChat(peerID, .noProfile)))
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
		guard room.summary?.membership == .join else { completion(nil); return }
		room.leave { response in
			// TODO implement [forget](https://matrix.org/docs/spec/client_server/r0.6.1#id294) API call once it is available in matrix-ios-sdk
			room.close()
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
			room.close()
			if let error = response.error {
				elog("Failed leaving room: \(error.localizedDescription)")
			}
			// TODO implement [forget](https://matrix.org/docs/spec/client_server/r0.6.1#id294) API call once it is available in matrix-ios-sdk
			self.forget(rooms: leftoverRooms, completion: completion)
		}
	}

	/// Tries to recover from certain errors (currently only `M_FORBIDDEN`); must be called from `dQueue`.
	private func handle<T>(response: MXResponse<T>, in room: MXRoom, with peerID: PeerID, _ completion: @escaping (Result<T, ServerChatError>) -> Void) {
		guard (response.error as? NSError)?.userInfo["errcode"] as? String == kMXErrCodeStringForbidden else {
			completion(response.toResult().mapError { .sdk($0) })
			return
		}

		self.forget(room: room) { error in
			dlog("forgetting room after unpin completed with \(error?.localizedDescription ?? "no error")")
		}
		_ = self.roomsForPeerIDs.removeValue(forKey: peerID)

		AccountController.use {
			$0.updatePinStatus(of: peerID, force: true) { pinState in
				self.dQueue.async {
					guard pinState == .pinMatch else {
						completion(.failure(.cannotChat(peerID, .unmatched)))
						return
					}

					// TODO: knock on room instead once that is supported by MatrixSDK
					self.createRoom(with: peerID) { createRoomResult in
						dlog("creating new room after re-pin completed: \(createRoomResult)")
						completion(response.toResult().mapError { .sdk($0) })
					}
				}
			}
		}
	}

	/// Join the Matrix room identified by `roomId`.
	private func join(roomId: String, with peerID: PeerID) {
		AccountController.use { ac in
			ac.updatePinStatus(of: peerID, force: false) { pinState in
				guard pinState == .pinMatch else { return }

				self.dQueue.async {
					self.session.joinRoom(roomId) { joinResponse in
						guard joinResponse.isSuccess else {
							elog("Cannot join room \(roomId): \(joinResponse.error ?? unexpectedNilError())")
							return
						}
						// we do not addRoomAndListenToEvents here, since we do it in the mxRoomInitialSync notification
					}
				}
			}
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

			dlog("processing server chat member event type \(memberContent.membership ?? "<nil>") in room \(event.roomId ?? "<nil>") from \(eventUserId).")

			switch memberContent.membership {
			case kMXMembershipStringJoin:
				guard eventUserId != self.userId, let peerID = peerIDFrom(serverChatUserId: eventUserId) else { return }
				ServerChatNotificationName.readyToChat.post(for: peerID)

			case kMXMembershipStringInvite:
				guard eventUserId == self.userId else {
					// we are only interested in invites for us
					ilog("Received invite event from sender other than us.")
					return
				}

				// check whether we actually have a pin match with this person
				guard let peerID = peerIDFrom(serverChatUserId: event.sender) else {
					elog("Cannot construct PeerID from userId \(event.sender ?? "<nil>").")
					return
				}

				join(roomId: event.roomId, with: peerID)

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

				self.forget(room: room) { _error in
					dlog("Left empty room: \(String(describing: _error)).")
				}

				guard let peerID = peerIDFrom(serverChatUserId: eventUserId) else {
					elog("cannot construct PeerID from room directUserId \(eventUserId).")
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

	/// Initial setup routine; must be called on `AccountController.dQueue`!
	private func handleInitialRoom(_ room: MXRoom, ac: AccountController) {
		guard let theirUserId = room.directUserId else {
			elog("Room \(room.roomId ?? "<unknown>") is either not direct or the userId is not loaded.")
			return
		}
		guard let peerID = peerIDFrom(serverChatUserId: theirUserId) else {
			elog("Server chat userId \(theirUserId) is not a PeerID.")
			return
		}

		let isMatch = ac.hasPinMatch(peerID)

		room.members { membersResponse in
			guard let _members = membersResponse.value, let members = _members,
				  let ourMember = members.members.first(where: { $0.userId == self.userId}) else {
				flog("We are not a member of room \(room).")
				return
			}

			guard isMatch || ourMember.membership == .leave || ourMember.membership == .ban else {
				self.forget(room: room) { error in
					error.map { dlog("forgetting non-leave/ban room with non-matched peer \(peerID.uuidString) failed: \($0)") }
				}
				return
			}

			switch ourMember.membership {
			case .invite:
				self.join(roomId: room.roomId, with: peerID)

			case .join:
				guard let theirMember = members.members.first(where: { $0.userId == theirUserId}) else {
					wlog("They are not a member of room \(room)")
					self.forget(room: room) { error in
						error.map { dlog("forgetting room with peer \(peerID.uuidString) when they are not part of the room failed: \($0)") }
					}
					return
				}

				switch theirMember.membership {
				case .unknown, .invite, .join:
					self.addRoomAndListenToEvents(room, for: peerID)
				case .leave, .ban:
					self.forget(room: room) { error in
						error.map { dlog("forgetting room with peer \(peerID.uuidString) after they left failed: \($0)") }
					}
				@unknown default:
					self.addRoomAndListenToEvents(room, for: peerID)
				}

			case .leave, .ban, .unknown:
				// ignored
				break

			@unknown default:
				// ignored
				break
			}
		}
	}

	/// Initial setup routine
	private func handleInitialRooms() {
		AccountController.use { ac in
			for room in self.session.rooms {
				self.handleInitialRoom(room, ac: ac)
			}
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

				self.handleInitialRooms()

				_ = self.session.listenToEvents([.roomMember]) { event, direction, state in
					self.process(memberEvent: event)
				}
				completion(response.error)
			}
		}
	}

	/// Observes relevant notifications in `NotificationCenter`.
	private func observeNotifications() {
		let pinStateChangeHandler: (PeerID, Notification) -> Void = { [weak self] peerID, _ in
			guard let strongSelf = self, let room = strongSelf.roomsForPeerIDs.removeValue(forKey: peerID) else { return }

			// we don't need to use dQueue here, since forget is not mutating.
			strongSelf.forget(room: room) { _error in
				dlog("Left room: \(String(describing: _error)).")
			}
		}

		notificationObservers.append(AccountController.NotificationName.unpinned.addAnyPeerObserver(pinStateChangeHandler))
		notificationObservers.append(AccountController.NotificationName.unmatch.addAnyPeerObserver(pinStateChangeHandler))

		notificationObservers.append(AccountController.NotificationName.pinMatch.addAnyPeerObserver { [weak self] peerID, _ in
			guard let strongSelf = self else { return }

			// Creates a room with `peerID` for chatting; also notifies them over the internet that we have a match.
			strongSelf.dQueue.async {
				strongSelf.createRoom(with: peerID) { result in
					result.error.map { dlog("inviting \(peerID) failed: \($0)") }
				}
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