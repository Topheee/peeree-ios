//
//  ServerChatController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 12.05.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import Foundation
import MatrixSDK
import PeereeCore

/// Internal implementaion of the `ServerChat` protocol.
///
/// Note: __All__ functions must be called on `dQueue`!
final class ServerChatController: ServerChat {
	// MARK: - Public and Internal

	/// Creates a `ServerChatController`.
	init(peerID: PeerID, restClient: MXRestClient, dataSource: ServerChatDataSource, dQueue: DispatchQueue) {
		self.peerID = peerID
		self.dataSource = dataSource
		self.dQueue = dQueue

		session = ThreadSafeCallbacksMatrixSession(session: MXSession(matrixRestClient: restClient)!, queue: dQueue)
	}

	// MARK: Variables

	/// Information provider for external dependencies.
	let dataSource: ServerChatDataSource

	/// Informed party.
	weak var delegate: ServerChatDelegate?

	/// Informed party.
	weak var conversationDelegate: (any ServerChatViewModelDelegate)?

	// MARK: Methods

	/// this will close the underlying session and invalidate the global ServerChatController instance.
	func close() {
		for observer in notificationObservers { NotificationCenter.default.removeObserver(observer) }
		notificationObservers.removeAll()

		self.roomIdsListeningOn.removeAll()

		// *** roughly based on MXKAccount.closeSession(true) ***
		session.scanManager?.deleteAllAntivirusScans()
		session.aggregations?.resetData()
		session.close()
	}

	// as this method also invalidates the deviceId, other users cannot send us encrypted messages anymore. So we never logout except for when we delete the account.
	/// this will close the underlying session. Do not re-use it (do not make any more calls to this ServerChatController instance).
	func logout(_ completion: @escaping (Error?) -> Void) {
		session.extensiveLogout { error in
			self.close()
			completion(error)
		}
	}

	/// Removes the server chat account permanently.
	func deleteAccount(password: String, _ completion: @escaping (ServerChatError?) -> Void) {
		session.deactivateAccount(withAuthParameters: ["type" : kMXLoginFlowTypePassword, "user" : self.userId, "password" : password], eraseAccount: true) { response in
			guard response.isSuccess else { completion(.sdk(response.error ?? unexpectedNilError())); return }

			// it seems we need to log out after we deleted the account
			self.logout { _error in
				_error.map { elog(Self.LogTag, "Logout after account deletion failed: \($0.localizedDescription)") }
				// do not escalate the error of the logout, as it doesn't mean we didn't successfully deactivated the account
				completion(nil)
			}
		}
	}

	// MARK: ServerChat

	/// Checks whether `peerID` can receive or messages.
	func canChat(with peerID: PeerID, _ completion: @escaping (ServerChatError?) -> Void) {
		session.getJoinedOrInvitedRoom(with: peerID.serverChatUserId, bothJoined: true) { completion($0 != nil ? nil : .cannotChat(peerID, .notJoined)) }
	}

	/// Send a `message` to `peerID`.
	func send(message: String, to peerID: PeerID, _ completion: @escaping (Result<String?, ServerChatError>) -> Void) {
		let directRooms = session.directRooms(with: peerID.serverChatUserId)
		guard !directRooms.isEmpty else {
			completion(.failure(.cannotChat(peerID, .notJoined)))
			return
		}

		for room in directRooms {
			var event: MXEvent? = nil
			room.sendTextMessage(message, localEcho: &event) { response in
				switch response {
				case .success(_):
					break
				case .failure(let error):
					self.recoverFrom(sdkError: error as NSError, in: room, with: peerID) { recoveryResult in
						switch recoveryResult {
						case .success(let shouldRetry):
							guard shouldRetry else { return }

							room.sendTextMessage(message, localEcho: &event) { retryResponse in
								completion(retryResponse.mapError { .sdk($0) })
							}

						case .failure(let failure):
							completion(.failure(failure))
						}
					}
				}
			}
		}
	}

	func fetchMessagesFromStore(peerID: PeerID, count: Int) {
		self.dQueue.async {
			self.session.directRooms(with: peerID.serverChatUserId).forEach { room in
				self.loadEventsFromDisk(count, in: room, with: peerID)
			}
		}
	}

	/// Ongoing paginations per `PeerID`; use only from dQueue.
	private var paginations = Set<PeerID>()

	/// DOES NOT WORK!
	func paginateUp(peerID: PeerID, count: Int, _ completion: @escaping (Error?) -> ()) {
		self.dQueue.async {

			// pagination fails with 'M_INVALID_PARAM': Invalid from parameter: malformed sync token
			guard !self.paginations.contains(peerID) else {
				completion(createApplicationError(localizedDescription: "already paginating"))
				return
			}

			let timelines = self.session.directRooms(with: peerID.serverChatUserId).compactMap { self.roomTimelines[$0.roomId] }

			guard !timelines.isEmpty else {
				completion(createApplicationError(localizedDescription: "no room timeline found"))
				return
			}

			self.paginations.insert(peerID)

			timelines.forEach { timeline in
				guard timeline.canPaginate(.backwards) else {
					completion(createApplicationError(localizedDescription: "Cannot paginate timeline up"))
					return
				}

				timeline.paginate(UInt(count), direction: .backwards, onlyFromStore: false) { response in
					self.paginations.remove(peerID)
					completion(response.error)
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
//			"format": "event_id_only",
			"default_payload": [
				"aps": [
//					"mutable-content": 1,
					"alert": [
						"loc-key": "MSG_FROM_USER",
						"loc-args": [] as [String]
					] as [String : Any]
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
			switch response {
			case .failure(let error):
				elog(Self.LogTag, "setPusher() failed: \(error)")
				self.delegate?.configurePusherFailed(error)
			case .success():
				dlog(Self.LogTag, "setPusher() was successful.")
			}
		}
	}

	/// Sends read receipts for all messages with `peerID`.
	func markAllMessagesRead(of peerID: PeerID) {
		session.getJoinedOrInvitedRoom(with: peerID.serverChatUserId, bothJoined: true) { room in
			// unfortunately, the MatrixSDK does not support "private" read receipts at this point, but we need this for a correct application icon badge count on remote notification receipt
			room?.markAllAsRead()
		}
	}

	public func set(lastRead date: Date, of peerID: PeerID) {
		lastReads[peerID] = date
		Task {
			do {
				try await persistence.set(lastRead: date, of: peerID)
			} catch {
				self.delegate?.encodingPersistedChatDataFailed(with: error)
			}
		}

		DispatchQueue.main.async {
			self.conversationDelegate?.persona(of: peerID).set(lastReadDate: date)
		}
	}

	/// Create chat room with `peerID`.
	func initiateChat(with peerID: PeerID) {
		// Creates a room with `peerID` for chatting; also notifies them over the internet that we have a match.
		self.getOrCreateRoom(with: peerID) { result in
			switch result {
			case .success(let success):
				if success.summary?.membership == .invite {
					self.join(roomId: success.roomId, with: peerID)
				}
			case .failure(let failure):
				self.delegate?.serverChatInternalErrorOccured(failure)
			}
		}
	}

	/// Leave all chat rooms with `peerID`.
	func leaveChat(with peerID: PeerID) {
		lastReads.removeValue(forKey: peerID)
		Task {
			do {
				try await persistence.removePeerData([peerID])
			} catch {
				self.delegate?.encodingPersistedChatDataFailed(with: error)
			}
		}
		
		session.directRooms?[peerID.serverChatUserId].map {
			forgetRooms($0) {}
		}

		DispatchQueue.main.async {
			self.conversationDelegate?.removePersona(of: peerID)
		}
	}

	// MARK: - Private

	// MARK: Static Constants

	// Log tag.
	private static let LogTag = "ServerChatController"

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
	private let session: ThreadSafeCallbacksMatrixSession

	private let persistence = PersistedServerChatDataController(filename: "serverchats.json")

	/// Last read timestamps.
	private var lastReads: [PeerID : Date] = [:]

	// MARK: Variables

	/// Matrix userId based on user's PeerID.
	private var userId: String { return peerID.serverChatUserId }

	/// The rooms we already listen on for message events; must be used on `dQueue`.
	private var roomIdsListeningOn = [String : PeerID]()

	/// The timelines of rooms we are listening on; must be used on `dQueue`.
	private var roomTimelines = [String : MXEventTimeline]()

	/// All references to NotificationCenter observers by this object.
	private var notificationObservers: [Any] = []

	// MARK: Methods

	/// Retrieves or creates a room with `peerID`.
	private func getOrCreateRoom(with peerID: PeerID, _ completion: @escaping (Result<MXRoom, ServerChatError>) -> Void) {
		session.getJoinedOrInvitedRoom(with: peerID.serverChatUserId, bothJoined: false) { room in
			if let room = room {
				completion(.success(room))
				return
			}

			// FUCK THIS SHIT: session.matrixRestClient.profile(forUser: peerUserId) crashes on my iPad with iOS 9.2
			if #available(iOS 10, *) {
				guard let client = self.session.matrixRestClient else {
					completion(.failure(.fatal(unexpectedNilError())))
					return
				}

				client.profile(forUser: peerID.serverChatUserId) { response in
					guard response.isSuccess else {
						completion(.failure(.cannotChat(peerID, .noProfile)))
						return
					}
					self.reallyCreateRoom(with: peerID, completion: completion)
				}
			} else {
				self.reallyCreateRoom(with: peerID, completion: completion)
			}
		}
	}

	/// Create a direct room for chatting with `peerID`.
	private func reallyCreateRoom(with peerID: PeerID, completion: @escaping (Result<MXRoom, ServerChatError>) -> Void) {
		let peerUserId = peerID.serverChatUserId
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

				self.listenToEvents(in: room, with: peerID)
				completion(.success(room))
			}
		} failure: { error in
			completion(.failure(.sdk(error ?? unexpectedNilError())))
		}
	}

	private var storedMessagesEnumerators = [String : MXEventsEnumerator]()

	/// Call only from dQueue!
	private func loadEventsFromDisk(_ eventCount: Int, in room: MXRoom, with peerID: PeerID) {
		guard let roomID = room.roomId, let timelineID = self.roomTimelines[roomID]?.timelineId else { return }

		let enumerator: MXEventsEnumerator
		if let existingEnumerator = storedMessagesEnumerators[roomID] {
			enumerator = existingEnumerator
		} else {
			guard let newEnumerator = room.enumeratorForStoredMessages else { return }
			enumerator = newEnumerator
			storedMessagesEnumerators[roomID] = newEnumerator
		}

		let ourUserId = self.userId
		let lastReadDate = lastReads[peerID] ?? Date.distantPast

		// Unencrypted stored messages.
		var catchUpMissedMessages = [ChatMessage]()
		// Encrypted stored messages.
		var encryptedEvents = [MXEvent]()
		var unreadMessages = 0

		catchUpMissedMessages.reserveCapacity(eventCount)
		encryptedEvents.reserveCapacity(eventCount)

		while let event = enumerator.nextEvent {
			switch event.eventType {
			case .roomMessage:
				do {
					let messageEvent = try ChatMessage(messageEvent: event, ourUserId: ourUserId)
					catchUpMissedMessages.append(messageEvent)
					if messageEvent.timestamp > lastReadDate { unreadMessages += 1 }
				} catch let error {
					elog(Self.LogTag, "\(error)")
				}
			case .roomEncrypted:
				encryptedEvents.append(event)
			default:
				break
			}

			if encryptedEvents.count > eventCount || catchUpMissedMessages.count > eventCount { break }
		}

		catchUpMissedMessages.reverse()

//#if os(iOS)
		// decryptEvents() is somehow not available on macOS
		self.session.decryptEvents(encryptedEvents, inTimeline: timelineID) { failedEvents in
			if let failedEvents, failedEvents.count > 0 {
				for failedEvent in failedEvents {
					wlog(Self.LogTag, "Couldn't decrypt event: \(failedEvent.eventId ?? "<nil>"). Reason: \(failedEvent.decryptionError ?? unexpectedNilError())")
				}
			}

			// these are all messages that we have seen earlier already, but we need to decryt them again apparently
			var catchUpDecryptedMessages = [ChatMessage]()
			for event in encryptedEvents {
				switch event.eventType {
				case .roomMessage:
					do {
						let messageEvent = try ChatMessage(messageEvent: event, ourUserId: ourUserId)
						catchUpDecryptedMessages.append(messageEvent)
						if messageEvent.timestamp > lastReadDate { unreadMessages += 1 }
					} catch let error {
						elog(Self.LogTag, "\(error)")
					}
				default:
					break
				}
			}
			catchUpDecryptedMessages.reverse()
			catchUpDecryptedMessages.append(contentsOf: catchUpMissedMessages)
			if catchUpDecryptedMessages.count > 0 {
				let sentCatchUpDecryptedMessages = catchUpDecryptedMessages
				let sentUnreadMessages = unreadMessages
				DispatchQueue.main.async {
					self.conversationDelegate?.catchUp(messages: sentCatchUpDecryptedMessages, sorted: true, unreadCount: sentUnreadMessages, with: peerID)
				}
			}
		}
//#endif
	}

	/// Listens to events in `room`; must be called on `dQueue`.
	private func listenToEvents(in room: MXRoom, with peerID: PeerID) {
		guard let roomId = room.roomId else {
			flog(Self.LogTag, "fuck is this")
			return
		}

		dlog(Self.LogTag, "listenToEvents(in room: \(roomId), with peerID: \(peerID)).")
		guard roomIdsListeningOn[roomId] == nil else { return }
		roomIdsListeningOn[roomId] = peerID

		room.liveTimeline { timeline in
			guard let timeline else {
				elog(Self.LogTag, "No timeline retrieved.")
				self.roomIdsListeningOn.removeValue(forKey: room.roomId)
				return
			}

			self.roomTimelines[room.roomId] = timeline

			self.loadEventsFromDisk(10, in: room, with: peerID)
		}
	}

	/// Tries to leave (and forget [once supported by the SDK]) `room`.
	private func forgetRoom(_ roomId: String, completion: @escaping (Error?) -> Void) {
		session.leaveRoom(roomId) { response in
			self.roomTimelines.removeValue(forKey: roomId)?.destroy()
			self.roomIdsListeningOn.removeValue(forKey: roomId)

			if let err = response.error as? NSError, MXError.isMXError(err),
			   err.userInfo["errcode"] as? String == kMXErrCodeStringUnknown,
			   err.userInfo["error"] as? String == "user \"\(self.peerID.serverChatUserId)\" is not joined to the room (membership is \"leave\")" {
				// otherwise, this will keep on as a zombie
				self.session.store?.deleteRoom(roomId)
			}

			completion(response.error)
		}
	}

	/// Tries to leave (and forget [once supported]) <code>rooms</code>, ignoring any errors
	private func forgetRooms(_ roomIds: [String], completion: @escaping () -> Void) {
		var leftoverRooms = roomIds // inefficient as hell: always creates a whole copy of the array
		guard let roomId = leftoverRooms.popLast() else {
			completion()
			return
		}
		forgetRoom(roomId) { error in
			error.map { elog(Self.LogTag, "Failed leaving room \(roomId): \($0.localizedDescription)") }
			self.forgetRooms(leftoverRooms, completion: completion)
		}
	}

	/// Tries to recover from certain errors (currently only `M_FORBIDDEN`); must be called from `dQueue`.
	private func recoverFrom(sdkError: NSError, in room: MXRoom, with peerID: PeerID, _ completion: @escaping (Result<Bool, ServerChatError>) -> Void) {
		if let matrixErrCode = sdkError.userInfo["errcode"] as? String {
			// this is a MXError

			switch matrixErrCode {
			case kMXErrCodeStringForbidden:
				self.forgetRoom(room.roomId) { error in
					dlog(Self.LogTag, "forgetting room after we got a forbidden error: \(error?.localizedDescription ?? "no error")")

					self.refreshPinStatus(of: peerID, force: true, {
						self.dQueue.async {
							// TODO: knock on room instead once that is supported by MatrixSDK
							self.getOrCreateRoom(with: peerID) { createRoomResult in
								dlog(Self.LogTag, "creating new room after re-pin completed: \(createRoomResult)")
								completion(.success(true))
							}
						}
					}, {
						completion(.failure(.cannotChat(peerID, .unmatched)))
					})
				}
			default:
				completion(.failure(.sdk(sdkError)))
			}
		} else {
			// NSError

			switch sdkError.code {
			case Int(MXEncryptingErrorUnknownDeviceCode.rawValue):
				// we trust all devices by default - this is not the best security, but helps us right now
				guard let crypto = session.crypto,
						let unknownDevices = sdkError.userInfo[MXEncryptingErrorUnknownDeviceDevicesKey] as? MXUsersDevicesMap<MXDeviceInfo> else {
					completion(.failure(.fatal(sdkError)))
					return
				}

				crypto.trustAll(devices: unknownDevices) { error in
					if let error = error {
						completion(.failure(.sdk(error)))
					} else {
						completion(.success(true))
					}
				}

			default:
				completion(.failure(.sdk(sdkError)))
			}
		}
	}

	/// Join the Matrix room identified by `roomId`.
	private func join(roomId: String, with peerID: PeerID) {
		session.joinRoom(roomId) { joinResponse in
			switch joinResponse {
			case .success(let room):
				self.listenToEvents(in: room, with: peerID)
			case .failure(let error):
				guard (error as NSError).domain != kMXNSErrorDomain && (error as NSError).code != kMXRoomAlreadyJoinedErrorCode else {
					dlog(Self.LogTag, "tried again to join room \(roomId) for peerID \(peerID).")
					return
				}

				elog(Self.LogTag, "Cannot join room \(roomId): \(error)")
				self.delegate?.cannotJoinRoom(error)
			}
		}
	}

	/// Handles room member events.
	private func process(memberEvent event: MXEvent) {
		switch event.eventType {
		case .roomMember:
			guard let memberContent = MXRoomMemberEventContent(fromJSON: event.content),
				  let eventUserId = event.stateKey,
				  let roomId = event.roomId else {
				flog(Self.LogTag, "Hard condition not met in membership event.")
				return
			}

			dlog(Self.LogTag, "processing server chat member event type \(memberContent.membership ?? "<nil>") in room \(roomId) from \(eventUserId).")

			switch memberContent.membership {
			case kMXMembershipStringJoin:
				guard eventUserId != self.userId, let peerID = peerIDFrom(serverChatUserId: eventUserId) else { return }

				DispatchQueue.main.async {
					self.conversationDelegate?.persona(of: peerID).readyToChat = true
				}

			case kMXMembershipStringInvite:
				guard eventUserId == self.userId else {
					// we are only interested in invites for us
					dlog(Self.LogTag, "Received invite event for other user.")
					return
				}

				// check whether we actually have a pin match with this person
				guard let peerID = peerIDFrom(serverChatUserId: event.sender) else {
					elog(Self.LogTag, "Cannot construct PeerID from userId \(event.sender ?? "<nil>").")
					return
				}

				// check whether we still have a pin match with this person
				dataSource.hasPinMatch(with: [peerID], forceCheck: false) { checkedPeerID, result in
					guard result else {
						self.dataSource.hasPinMatch(with: [peerID], forceCheck: true) { peerID, hasPinMatch in
							self.dQueue.async {
								if hasPinMatch {
									self.join(roomId: roomId, with: peerID)
								} else {
									self.leaveChat(with: peerID)
								}
							}
						}
						return
					}

					assert(checkedPeerID == peerID)
					self.dQueue.async {
						self.join(roomId: roomId, with: peerID)
					}
				}

			case kMXMembershipStringLeave:
				guard eventUserId != self.userId else {
					// we are only interested in leaves from other people
					// ATTENTION: we seem to also receive this event, when we first get to know of this room - i.e., when we are invited, we first get the event that we left (or that we are in the state "leave"). Kind of strange, but yeah.
					dlog(Self.LogTag, "Received our leave event.")
					return
				}

				self.forgetRoom(event.roomId) { _error in
					dlog(Self.LogTag, "Left empty room: \(String(describing: _error)).")
				}

				guard let peerID = peerIDFrom(serverChatUserId: eventUserId) else {
					elog(Self.LogTag, "cannot construct PeerID from room directUserId \(eventUserId).")
					return
				}

				// check whether we still have a pin match with this person
				refreshPinStatus(of: peerID, force: true, nil)

			default:
				wlog(Self.LogTag, "Unexpected room membership \(memberContent.membership ?? "<nil>").")
			}
		default:
			wlog(Self.LogTag, "Received global event we didn't listen for: \(event.type ?? "<unknown event type>").")
			break
		}
	}

	/// Initial setup routine
	private func handleInitialRooms() {
		guard let directChatPeerIDs = session.directRooms?.compactMap({ (key, value) in
			// This is a stupid hotfix, but somehow the left rooms are not deleted, even if we instruct it.
			value.reduce(false) { partialResult, roomId in
				partialResult || session.roomSummary(withRoomId: roomId)?.membership == .join
			} ? peerIDFrom(serverChatUserId: key) : nil
		}), directChatPeerIDs.count > 0 else { return }

		dataSource.hasPinMatch(with: directChatPeerIDs, forceCheck: false) { peerID, result in
			if result {
				// this may cause us to be throttled down, since we potentially start many requests in parallel here
				self.fixRooms(with: peerID)
			} else {
				self.leaveChat(with: peerID)
			}
		}
	}

	/// Handles all the different room states of all the room with `peerID`.
	private func fixRooms(with peerID: PeerID) {
		session.directRoomInfos(with: peerID.serverChatUserId) { infos in
			// always leave all rooms where the other one already left
			let theyJoinedOrInvited = infos.filter { info in
				let theyIn = info.theirMembership == .join || info.theirMembership == .invite || info.theirMembership == .unknown

				if !theyIn {
					wlog(Self.LogTag, "triaging room \(info.room.roomId ?? "<nil>") with peerID \(peerID).")
					self.forgetRoom(info.room.roomId) { error in
						error.map { elog(Self.LogTag, "leaving room failed: \($0)")}
					}
				}

				return theyIn
			}

			if let readyRoom = theyJoinedOrInvited.first(where: { $0.theirMembership == .join && $0.ourMembership == .join }) {
				self.forgetRooms(theyJoinedOrInvited.compactMap { $0.room.roomId != readyRoom.room.roomId ? $0.room.roomId : nil }) {}
				self.listenToEvents(in: readyRoom.room, with: peerID)
				
				DispatchQueue.main.async {
					self.conversationDelegate?.persona(of: peerID).readyToChat = true
				}
			} else if let invitedRoom = theyJoinedOrInvited.first(where: { $0.ourMembership == .invite }) {
				// it is very likely that they are joined here, since they needed to be when they invited us
				self.join(roomId: invitedRoom.room.roomId, with: peerID)
				self.forgetRooms(theyJoinedOrInvited.compactMap { $0.room.roomId != invitedRoom.room.roomId ? $0.room.roomId : nil }) {}
			} else if let invitedRoom = theyJoinedOrInvited.first(where: { $0.theirMembership == .invite }) {
				// we chose the first room we invited them and drop the rest
				self.forgetRooms(theyJoinedOrInvited.compactMap { $0.room.roomId != invitedRoom.room.roomId ? $0.room.roomId : nil }) {}
				self.listenToEvents(in: invitedRoom.room, with: peerID)
			} else {
				self.reallyCreateRoom(with: peerID) { result in
					result.error.map {
						elog(Self.LogTag, "failed to really create room with \(peerID): \($0)")
						self.delegate?.serverChatInternalErrorOccured($0)
					}
				}
			}
		}
	}

	/// Refreshes the pin status with the Peeree server, forgets all rooms with `peerID` if we do not have a pin match, and calls `pinMatchedAction` or `noPinMatchAction` depending on the pin status.
	private func refreshPinStatus(of peerID: PeerID, force: Bool, _ pinMatchedAction: (() -> Void)?, _ noPinMatchAction: (() -> Void)? = nil) {
		dataSource.hasPinMatch(with: [peerID], forceCheck: force) { checkedPeerID, result in
			assert(checkedPeerID == peerID)
			if result {
				pinMatchedAction?()
			} else {
				self.leaveChat(with: peerID)
				noPinMatchAction?()
			}
		}
	}

	/// Parses `event` and informs the rest of the app with the contents.
	private func process(messageEvent event: MXEvent) {
		guard let peerID = roomIdsListeningOn[event.roomId ?? ""],
			  let convDelegate = self.conversationDelegate else { return }

		do {
			let ourUserId = self.peerID.serverChatUserId
			let messageEvent = try ChatMessage(messageEvent: event, ourUserId: ourUserId)

			DispatchQueue.main.async {
				convDelegate.new(message: messageEvent, inChatWithConversationPartner: peerID)
			}
		} catch let error {
			elog(Self.LogTag, "\(error)")
		}
	}

	/// Begin the session.
	func start(_ completion: @escaping (Error?) -> Void) {
		observeNotifications()

		guard let sessionCreds = session.credentials else {
			completion(unexpectedNilError())
			return
		}

		Task {
			do {
				try await persistence.loadInitialData()
			} catch {
				self.delegate?.decodingPersistedChatDataFailed(with: error)
			}

			let lastReads = await persistence.lastReads

			self.lastReads = lastReads

			if let d = self.conversationDelegate {
				DispatchQueue.main.async {
					for (peerID, lastReadDate) in lastReads {
						d.persona(of: peerID).set(lastReadDate: lastReadDate)
					}
				}
			}

		let store = MXFileStore(credentials: sessionCreds)
		self.session.setStore(store) { setStoreResponse in
			guard setStoreResponse.isSuccess else {
				completion(setStoreResponse.error ?? unexpectedNilError())
				return
			}

			let filter = MXFilterJSONModel.syncFilter(withMessageLimit: 10)!
			self.session.start(withSyncFilter: filter) { response in
				guard response.isSuccess else {
					completion(response.error ?? unexpectedNilError())
					return
				}

				self.handleInitialRooms()

				_ = self.session.listenToEvents { event, direction, customObject in
					dlog(Self.LogTag, "event \(event.eventId ?? "<nil>") in room \(event.roomId ?? "<nil>")")

					guard let decryptionError = event.decryptionError as? NSError,
						  let peerID = peerIDFrom(serverChatUserId: event.sender) else { return }

					// Unfortunately, unrecoverable decryption errors may occasionally occur.
					// For instance, I had the case that the iPhone was in a direct room with an Android and was itself able to send messages, which the Android was able to receive and decrypt.
					// However, once the Android sent a message, it raised the infamous "UISI" (unknown inbound session id) error on the iPhone's side.
					// There are numerous reasons for this error and the library authors do not seem to be able to cope with the problem.
					// See for instance this issue: https://github.com/vector-im/element-web/issues/2996

					// The main problem for us is that the sending device (the Android) did not get any feedback at all that the message could not be decrypted.
					// Thus from the Android perspective it looks like the message was sent (and received) successfully. THIS IS BAD.

					// I cannot find a way to recover from these UISI errors. And they happened to me before, too.
					// There is something called [Device Dehydration](https://github.com/uhoreg/matrix-doc/blob/dehydration/proposals/2697-device-dehydration.md), but that seems to cover another purpose.
					// There is also this (implemented) proposal: https://github.com/uhoreg/matrix-doc/blob/dehydration/proposals/1719-olm_unwedging.md, which should actually cover broken rooms (they call them "wedged"). However, looking at the source code ([MXCrypto decryptEvent2:inTimeline:]) of the matrix-ios-sdk, this automatic handling only applies to `MXDecryptingErrorBadEncryptedMessageCode` errors, but not `MXDecryptingErrorUnknownInboundSessionIdCode` ones.

					// The only option I see is to leave the room and create a new one.

					self.delegate?.decryptionError(decryptionError, peerID: peerID) {
						self.forgetRoom(event.roomId) { forgetError in
							forgetError.map { dlog(Self.LogTag, "forgetting room with broken encryption failed: \($0)") }

							self.getOrCreateRoom(with: peerID) { result in
								dlog(Self.LogTag, "replaced room with broken encryption with result \(result)")
							}
						}
					}
				}

				_ = self.session.listenToEvents([.roomMember, .roomMessage]) { event, direction, state in
					switch event.eventType {
					case .roomMessage:
						self.process(messageEvent: event)
					default:
						guard direction == .forwards else { return }
						self.process(memberEvent: event)
					}
				}
				completion(response.error)
			}
		} }
	}

	/// Observes relevant notifications in `NotificationCenter`.
	private func observeNotifications() {
		// mxRoomSummaryDidChange fires very often, but at some point the room contains a directUserId
		// mxRoomInitialSync does not fire that often and contains the directUserId only for the receiver. But that is okay, since the initiator of the room knows it anyway
		notificationObservers.append(NotificationCenter.default.addObserver(forName: .mxRoomInitialSync, object: nil, queue: nil) { [weak self] notification in
			guard let strongSelf = self, let room = notification.object as? MXRoom else { return }

			strongSelf.dQueue.async {
				guard let userId = room.directUserId else {
					elog(Self.LogTag, "Found non-direct room \(room.roomId ?? "<nil>").")
					return
				}
				guard let peerID = peerIDFrom(serverChatUserId: userId) else {
					elog(Self.LogTag, "Found room with non-PeerID \(userId).")
					return
				}

				strongSelf.listenToEvents(in: room, with: peerID)
			}
		})
	}
}
