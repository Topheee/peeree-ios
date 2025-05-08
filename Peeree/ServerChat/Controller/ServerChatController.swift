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
@ChatActor
final class ServerChatController: ServerChat {
	// MARK: - Public and Internal

	/// Creates a `ServerChatController`.
	init(peerID: PeerID, restClient: MXRestClient, dataSource: ServerChatDataSource) {
		self.peerID = peerID
		self.dataSource = dataSource
		self.mxClient = restClient

		session = ThreadSafeCallbacksMatrixSession(session: MXSession(matrixRestClient: restClient)!)
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
	func logout() async throws {
		defer { self.close() }

		try await self.session.extensiveLogout()

		await self.persistence.clear()
	}

	/// Removes the server chat account permanently.
	func deleteAccount(password: String) async throws {
		do {
			let authParams: [String: Any] = [
				"type" : kMXLoginFlowTypePassword,
				"user" : self.userId,
				"password" : password]

			try await withCheckedThrowingContinuation { continuation in
				self.mxClient.deactivateAccount(
					withAuthParameters: authParams,
					eraseAccount: true) { response in
						continuation.resume(with: response)
					}
			}

			// it seems we need to log out after we deleted the account
			do {
				try await self.logout()
			} catch {
				elog(Self.LogTag, "Logout after account deletion failed:" +
					 error.localizedDescription)
				// do not escalate the error of the logout, as it doesn't mean
				// we didn't successfully deactivated the account
			}

			Task { @MainActor in
				await self.conversationDelegate?.clear()
			}
		} catch {
			throw ServerChatError.sdk(error)
		}
	}

	// MARK: ServerChat

	/// Checks whether `peerID` can receive or messages.
	func canChat(with peerID: PeerID) async throws {
		if await session.getJoinedOrInvitedRoom(
			with: peerID.serverChatUserId(self.mxClient),
			bothJoined: true) == nil {
			throw ServerChatError.cannotChat(peerID, .notJoined)
		}
	}

	/// Send a `message` to `peerID`.
	func send(message: String, to peerID: PeerID) async throws {
		let directRooms = session.directRooms(
			with: peerID.serverChatUserId(self.mxClient))

		guard !directRooms.isEmpty else {
			throw ServerChatError.cannotChat(peerID, .notJoined)
		}

		for room in directRooms {
			do {
				try await room.sendTextMessage(message)
			} catch {
				try await self.recoverFrom(sdkError: error as NSError,
										   in: room, with: peerID)

				// retry if recovery successful
				try await room.sendTextMessage(message)
			}
		}
	}

	func fetchMessagesFromStore(peerID: PeerID, count: Int) async {
		for room in self.session.directRooms(
			with: peerID.serverChatUserId(self.mxClient)) {
			await self.loadEventsFromDisk(count, in: room, with: peerID)
		}
	}

	/// DOES NOT WORK!
	func paginateUp(peerID: PeerID, count: Int) async throws {
		// pagination fails with 'M_INVALID_PARAM': Invalid from parameter: malformed sync token
		let timelines = self.session.directRooms(
			with: peerID.serverChatUserId(self.mxClient))
			.compactMap { $0.roomId }
			.compactMap { self.roomTimelines[$0] }

		guard !timelines.isEmpty else {
			throw createApplicationError(localizedDescription: "no room timeline found")
		}

		for timeline in timelines {
			guard timeline.canPaginate(.backwards) else {
				elog(Self.LogTag, "Cannot paginate timeline up")
				return
			}

			try? await timeline.paginate(UInt(count), direction: .backwards,
										 onlyFromStore: false)
		}
	}

	/// Set up APNs.
	func configurePusher(deviceToken: Data) async {
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
				Task {
					await self.delegate?.configurePusherFailed(error)
				}
			case .success():
				dlog(Self.LogTag, "setPusher() was successful.")
			}
		}
	}

	/// Sends read receipts for all messages with `peerID`.
	func markAllMessagesRead(of peerID: PeerID) async {
		let room = await session.getJoinedOrInvitedRoom(
			with: peerID.serverChatUserId(self.mxClient), bothJoined: true)
		// unfortunately, the MatrixSDK does not support "private" read
		// receipts at this point, but we need this for a correct application
		// icon badge count on remote notification receipt
		room?.markAllAsRead()
	}

	public func set(lastRead date: Date, of peerID: PeerID) async {
		lastReads[peerID] = date

		do {
			try await persistence.set(lastRead: date, of: peerID)
		} catch {
			await self.delegate?.encodingPersistedChatDataFailed(with: error)
		}

		Task { @MainActor in
			await self.conversationDelegate?
				.persona(of: peerID).set(lastReadDate: date)
		}
	}

	/// Create chat room with `peerID`.
	func initiateChat(with peerID: PeerID) async {
		// Creates a room with `peerID` for chatting; also notifies them over the internet that we have a match.
		do {
			let room = try await self.getOrCreateRoom(with: peerID)
			if let roomId = room.roomId,
			   room.summary?.membership == .invite {
				await self.join(roomId: roomId, with: peerID)
			}
		} catch {
			Task {
				await self.delegate?.serverChatInternalErrorOccured(error)
			}
		}
	}

	/// Leave all chat rooms with `peerID`.
	func leaveChat(with peerID: PeerID) async {
		lastReads.removeValue(forKey: peerID)
		Task {
			do {
				try await persistence.removePeerData([peerID])
			} catch {
				await self.delegate?.encodingPersistedChatDataFailed(with: error)
			}
		}
		
		if let rooms = self.session.directRooms?[peerID.serverChatUserId(self.mxClient)] {
			await self.forgetRooms(rooms)
		}

		await self.conversationDelegate?.removePersona(of: peerID)
	}

	func recreateRoom(with peerID: PeerID) async throws {
		let oldRoom = await self.session
			.getJoinedOrInvitedRoom(
				with: peerID.serverChatUserId(self.mxClient), bothJoined: false)

		_ = try await self.reallyCreateRoom(with: peerID)
		dlog(Self.LogTag, "Created new room to replace broken encryption.")

		if let room = oldRoom, let roomId = room.roomId {
			do {
				try await self.forgetRoom(roomId)
			} catch {
				dlog(Self.LogTag,
					 "forgetting room with broken encryption failed: "
					 + error.localizedDescription)
			}
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

	/// The Matrix REST client.
	private let mxClient: MXRestClient

	/// Matrix session.
	private let session: ThreadSafeCallbacksMatrixSession

	private let persistence = PersistedServerChatDataController(filename: "serverchats.json")

	/// Last read timestamps.
	private var lastReads: [PeerID : Date] = [:]

	// MARK: Variables

	/// Matrix userId based on user's PeerID.
	private var userId: String { return self.peerID.serverChatUserId(self.mxClient) }

	/// The rooms we already listen on for message events.
	private var roomIdsListeningOn = [String : PeerID]()

	/// All references to NotificationCenter observers by this object.
	private var notificationObservers: [Any] = []

	/// The timelines of rooms we are listening on.
	private var roomTimelines = [String : EventTimeline]()

	// MARK: Methods

	/// Retrieves or creates a room with `peerID`.
	private func getOrCreateRoom(with peerID: PeerID) async throws -> Room {
		let room = await session.getJoinedOrInvitedRoom(
			with: peerID.serverChatUserId(self.mxClient), bothJoined: false)
		if let room = room { return room }

		guard let client = self.session.matrixRestClient else {
			throw ServerChatError.fatal(unexpectedNilError())
		}

		do {
			_ = try await withCheckedThrowingContinuation { continuation in
				client.profile(forUser: peerID.serverChatUserId(self.mxClient))
				{ response in
					continuation.resume(with: response)
				}
			}
		} catch {
			throw ServerChatError.cannotChat(peerID, .noProfile)
		}

		return try await self.reallyCreateRoom(with: peerID)
	}

	/// Create a direct room for chatting with `peerID`.
	private func reallyCreateRoom(with peerID: PeerID) async throws -> Room {
		let peerUserId = peerID.serverChatUserId(self.mxClient)
		let roomParameters = MXRoomCreationParameters(forDirectRoomWithUser: peerUserId)
		roomParameters.visibility = kMXRoomDirectoryVisibilityPrivate
		do {
			let canEnableE2E = try await self.session
				.canEnableE2EByDefaultInNewRoom(withUsers: [peerUserId])

			guard canEnableE2E else {
				throw ServerChatError.cannotChat(peerID, .noEncryption)
			}

			roomParameters.initialStateEvents = [MXRoomCreationParameters.initialStateEventForEncryption(withAlgorithm: kMXCryptoMegolmAlgorithm)]

			let room = try await self.session
				.createRoom(parameters: roomParameters)

			await self.listenToEvents(in: room, with: peerID)

			return room
		} catch {
			throw ServerChatError.sdk(error)
		}
	}

	private var storedMessagesEnumerators = [String : MXEventsEnumerator]()

	/// Read past events from local storage.
	private func loadEventsFromDisk(_ eventCount: Int, in room: Room,
									with peerID: PeerID) async {
		guard let roomID = room.roomId,
			  let timelineID = self.roomTimelines[roomID]?.timelineId else {
			return
		}

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
					if !messageEvent.sent && messageEvent.timestamp > lastReadDate { unreadMessages += 1 }
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

		let failedEvents = await self.session
			.decryptEvents(encryptedEvents.map { Event($0) },
						   inTimeline: timelineID)

		// these are all messages that we have seen earlier already,
		// but we need to decryt them again apparently
		var catchUpDecryptedMessages = [ChatMessage]()

		if let failedEvents, failedEvents.count > 0 {
			var error: Error?
			for failedEvent in (failedEvents.map { $0.event }) {
				if error == nil {
					error = failedEvent.decryptionError
				}
				wlog(Self.LogTag, "Couldn't decrypt event: "
					 + "\(failedEvent.eventId ?? "<nil>"). Reason: "
					 + "\(failedEvent.decryptionError ?? unexpectedNilError())")
			}

			let failedMsgs = failedEvents.map {
				makeChatMessage(messageEvent: $0.event, ourUserId: ourUserId)
			}

			catchUpDecryptedMessages.append(contentsOf: failedMsgs)

			let e = error ?? unexpectedNilError()

			Task { @MainActor in
				await self.conversationDelegate?.persona(of: peerID).roomError = e
			}
		}

		// we only guarantee sortedness if no decryption errors occurred
		let sorted = catchUpDecryptedMessages.count == 0

		for event in encryptedEvents {
			switch event.eventType {
			case .roomMessage:
				let message = makeChatMessage(messageEvent: event, ourUserId: ourUserId)
				catchUpDecryptedMessages.append(message)
				if !message.sent && message.timestamp > lastReadDate { unreadMessages += 1 }
			default:
				break
			}
		}

		catchUpDecryptedMessages.reverse()
		catchUpDecryptedMessages.append(contentsOf: catchUpMissedMessages)

		guard catchUpDecryptedMessages.count > 0 else { return }
		let sentCatchUpDecryptedMessages = catchUpDecryptedMessages
		let sentUnreadMessages = unreadMessages
		guard let cd = self.conversationDelegate else { return }
		Task { @MainActor in
			cd.catchUp(messages: sentCatchUpDecryptedMessages, sorted: sorted, unreadCount: sentUnreadMessages, with: peerID)
		}
	}

	/// Listens to events in `room`.
	private func listenToEvents(in room: Room, with peerID: PeerID) async {
		guard let roomId = room.roomId else {
			flog(Self.LogTag, "fuck is this")
			return
		}

		dlog(Self.LogTag, "listenToEvents(in room: \(roomId), with peerID: \(peerID)).")
		guard roomIdsListeningOn[roomId] == nil else { return }
		roomIdsListeningOn[roomId] = peerID

		let timeline = await room.liveTimeline()

		guard let timeline else {
			elog(Self.LogTag, "No timeline retrieved.")
			self.roomIdsListeningOn.removeValue(forKey: roomId)
			return
		}

		self.roomTimelines[roomId] = timeline

		Task { @MainActor in
			await self.conversationDelegate?.persona(of: peerID)
				.technicalInfo = roomId
		}

		await self.loadEventsFromDisk(10, in: room, with: peerID)
	}

	/// Tries to leave (and forget [once supported by the SDK]) `room`.
	private func forgetRoom(_ roomId: String) async throws {
		do {
			try await session.leaveRoom(roomId)

			self.roomTimelines.removeValue(forKey: roomId)?.destroy()
			self.roomIdsListeningOn.removeValue(forKey: roomId)
		} catch {
			let err = error as NSError
			if MXError.isMXError(err),
				  err.userInfo["errcode"] as? String == kMXErrCodeStringUnknown,
				  err.userInfo["error"] as? String == "user \"\(self.peerID.serverChatUserId(self.mxClient))\" is not joined to the room (membership is \"leave\")" {
				// otherwise, this will keep on as a zombie
				self.session.store?.deleteRoom(roomId)
			} else {
				throw error
			}
		}
	}

	/// Tries to leave (and forget [once supported]) <code>rooms</code>, ignoring any errors
	private func forgetRooms(_ roomIds: [String]) async {
		var leftoverRooms = roomIds // inefficient as hell: always creates a whole copy of the array
		guard let roomId = leftoverRooms.popLast() else {
			return
		}

		do {
			try await self.forgetRoom(roomId)
		} catch {
			elog(Self.LogTag, "Failed leaving room \(roomId):"
				 + error.localizedDescription)
		}

		await self.forgetRooms(leftoverRooms)
	}

	/// Tries to recover from certain errors (currently only `M_FORBIDDEN`).
	private func recoverFrom(sdkError: NSError, in room: Room,
							 with peerID: PeerID) async throws {

		if let matrixErrCode = sdkError.userInfo["errcode"] as? String {
			// this is a MXError

			switch matrixErrCode {
			case kMXErrCodeStringForbidden:
				do {
					try await self.forgetRoom(room.roomId!)
				} catch {
					dlog(Self.LogTag, "forgetting room after we got a forbidden error failed:"
						 + error.localizedDescription)
					throw ServerChatError.fatal(error)
				}

				let pinMatch = try await self.refreshPinMatchStatus(of: peerID, force: true)
				guard pinMatch else {
					throw ServerChatError.cannotChat(peerID, .unmatched)
				}

				dlog(Self.LogTag, "creating new room after re-pin completed")

				// TODO: knock on room instead once that is supported by MatrixSDK
				_ = try await self.getOrCreateRoom(with: peerID)
			default:
				throw ServerChatError.sdk(sdkError)
			}
		} else {
			// NSError

			switch sdkError.code {
			case Int(MXEncryptingErrorUnknownDeviceCode.rawValue):
				// we trust all devices by default - this is not the best security, but helps us right now
				guard let crypto = session.crypto,
						let unknownDevices = sdkError.userInfo[MXEncryptingErrorUnknownDeviceDevicesKey] as? MXUsersDevicesMap<MXDeviceInfo> else {
					throw ServerChatError.fatal(sdkError)
				}

				let _: Bool = try await
				withCheckedThrowingContinuation { continuation in
					crypto.trustAll(devices: unknownDevices) { error in
						if let error {
							continuation.resume(
								throwing: ServerChatError.sdk(error))
						} else {
							continuation.resume(returning: true)
						}
					}
				}

			default:
				throw ServerChatError.sdk(sdkError)
			}
		}
	}

	/// Join the Matrix room identified by `roomId`.
	private func join(roomId: String, with peerID: PeerID) async {
		do {
			let room = try await session.joinRoom(roomId)
			await self.listenToEvents(in: room, with: peerID)
		} catch {
			guard (error as NSError).domain != kMXNSErrorDomain && (error as NSError).code != kMXRoomAlreadyJoinedErrorCode else {
				dlog(Self.LogTag, "tried again to join room \(roomId) for peerID \(peerID).")
				return
			}

			elog(Self.LogTag, "Cannot join room \(roomId): \(error)")
			Task {
				await self.delegate?.cannotJoinRoom(error)
			}
		}
	}

	/// Handles room member events.
	private func process(memberEvent event: MXEvent) async {
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

				Task { @MainActor in
					await self.conversationDelegate?.persona(of: peerID)
						.readyToChat = true
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

				do {
					// check whether we still have a pin match with this person
					var result = try await dataSource.hasPinMatch(with: peerID, forceCheck: false)

					guard result else {
						result = try await self.dataSource.hasPinMatch(with: peerID, forceCheck: true)

						if result {
							await self.join(roomId: roomId, with: peerID)
						} else {
							await self.leaveChat(with: peerID)
						}

						return
					}
				} catch {
					flog(Self.LogTag, "Error checking pin match: \(error)")
				}

				await self.join(roomId: roomId, with: peerID)

			case kMXMembershipStringLeave:
				guard eventUserId != self.userId else {
					// we are only interested in leaves from other people
					// ATTENTION: we seem to also receive this event, when we first get to know of this room - i.e., when we are invited, we first get the event that we left (or that we are in the state "leave"). Kind of strange, but yeah.
					dlog(Self.LogTag, "Received our leave event.")
					return
				}

				do {
					try await self.forgetRoom(event.roomId)
				} catch {
					dlog(Self.LogTag, "Left empty room: "
						 + error.localizedDescription)
				}

				guard let peerID = peerIDFrom(serverChatUserId: eventUserId) else {
					elog(Self.LogTag, "cannot construct PeerID from room directUserId \(eventUserId).")
					return
				}

				// check whether we still have a pin match with this person
				_ = try? await refreshPinMatchStatus(of: peerID, force: true)

			default:
				wlog(Self.LogTag, "Unexpected room membership \(memberContent.membership ?? "<nil>").")
			}
		default:
			wlog(Self.LogTag, "Received global event we didn't listen for: \(event.type ?? "<unknown event type>").")
			break
		}
	}

	/// Initial setup routine
	private func handleInitialRooms() async {
		guard let directChatPeerIDs = session.directRooms?.compactMap({ (key, value) in
			// This is a stupid hotfix, but somehow the left rooms are not deleted, even if we instruct it.
			value.reduce(false) { partialResult, roomId in
				partialResult || session.roomSummary(withRoomId: roomId)?.membership == .join
			} ? peerIDFrom(serverChatUserId: key) : nil
		}), directChatPeerIDs.count > 0 else { return }

		let directChatPeerIDSet = Set<PeerID>(directChatPeerIDs)

		// this may cause us to be throttled down, since we potentially start many requests in parallel here
		let pinMatches = await dataSource.pinMatches()

		// create new rooms for pin matches that we somehow missed to create
		for peerID in pinMatches.subtracting(directChatPeerIDSet) {
			_ = try? await self.getOrCreateRoom(with: peerID)
			// silently ignore errors with non-existing chat accounts for now
			//result.error.map { self.delegate?.cannotJoinRoom($0) }
		}

		// leave rooms with peers we are not matched with anymore
		for peerID in directChatPeerIDSet.subtracting(pinMatches) {
			await self.leaveChat(with: peerID)
		}

		for peerID in pinMatches.intersection(directChatPeerIDSet) {
			await self.fixRooms(with: peerID)
		}
	}

	/// Handles all the different room states of all the room with `peerID`.
	private func fixRooms(with peerID: PeerID) async {
		let infos = await self.session
			.directRoomInfos(with: peerID.serverChatUserId(self.mxClient))

		// always leave all rooms where the other one already left
		let theyJoinedOrInvited = infos.filter { info in
			let theyIn = info.theirMembership == .join || info.theirMembership == .invite || info.theirMembership == .unknown

			if !theyIn {
				wlog(Self.LogTag, "triaging room \(info.room.roomId ?? "<nil>") with peerID \(peerID).")
				Task {
					do {
						try await self.forgetRoom(info.room.roomId!)
					} catch {
						elog(Self.LogTag, "leaving room failed: "
							 + error.localizedDescription)
					}
				}
			}

			return theyIn
		}

		if let readyRoom = theyJoinedOrInvited.first(where: {
			$0.theirMembership == .join && $0.ourMembership == .join
		}) {
			await self.forgetRooms(theyJoinedOrInvited.compactMap {
				$0.room.roomId != readyRoom.room.roomId ? $0.room.roomId : nil
			})

			await self.listenToEvents(in: readyRoom.room, with: peerID)

			Task { @MainActor in
				await self.conversationDelegate?.persona(of: peerID)
					.readyToChat = true
			}
		} else if let invitedRoom = theyJoinedOrInvited.first(where: {
			$0.ourMembership == .invite }) {
			// it is very likely that they are joined here, since they needed to be when they invited us
			await self.join(roomId: invitedRoom.room.roomId!, with: peerID)
			await self.forgetRooms(theyJoinedOrInvited.compactMap {
				$0.room.roomId != invitedRoom.room.roomId ? $0.room.roomId : nil })
		} else if let invitedRoom = theyJoinedOrInvited.first(where: {
			$0.theirMembership == .invite }) {
			// we chose the first room we invited them and drop the rest
			await self.forgetRooms(theyJoinedOrInvited.compactMap {
				$0.room.roomId != invitedRoom.room.roomId ? $0.room.roomId : nil })
			await self.listenToEvents(in: invitedRoom.room, with: peerID)

			Task { @MainActor in
				/// we need to call `persona()` in order for the persona to be created and added to `matchedPeople`.
				await self.conversationDelegate?.persona(of: peerID)
					.readyToChat = false
			}
		} else {
			do {
				_ = try await self.reallyCreateRoom(with: peerID)
			} catch {
				elog(Self.LogTag, "failed to really create room with \(peerID): \(error.localizedDescription)")
				Task {
					await self.delegate?.serverChatInternalErrorOccured(error)
				}
			}
		}
	}

	/// Refreshes the pin status with the Peeree server. Returns if we have a pin match.
	/// Forgets all rooms with `peerID` if we do not have a pin match..
	private func refreshPinMatchStatus(of peerID: PeerID, force: Bool) async throws -> Bool {
		let result = try await dataSource.hasPinMatch(with: peerID, forceCheck: force)
		if result {
			return true
		} else {
			await self.leaveChat(with: peerID)
			return false
		}
	}

	/// Parses `event` and informs the rest of the app with the contents.
	private func process(messageEvent event: MXEvent) {
		guard let peerID = roomIdsListeningOn[event.roomId ?? ""],
			  let convDelegate = self.conversationDelegate else { return }

		let messageEvent = makeChatMessage(
			messageEvent: event, ourUserId: self.userId)

		Task { @MainActor in
			convDelegate.new(message: messageEvent, inChatWithConversationPartner: peerID)
		}
	}

	/// Begin the session.
	func start() async throws {
		observeNotifications()

		guard let sessionCreds = session.credentials else {
			throw unexpectedNilError()
		}

		do {
			try await persistence.loadInitialData()
		} catch {
			await self.delegate?.decodingPersistedChatDataFailed(with: error)
		}

		let lastReads = await persistence.lastReads

		self.lastReads = lastReads

		if let d = self.conversationDelegate {
			Task { @MainActor in
				for (peerID, lastReadDate) in lastReads {
					d.persona(of: peerID).set(lastReadDate: lastReadDate)
				}
			}
		}

		let store = MXFileStore(credentials: sessionCreds)
		try await self.session.setStore(store)

		let filter = MXFilterJSONModel.syncFilter(withMessageLimit: 10)!
		try await self.session.start(withSyncFilter: filter)

		await self.handleInitialRooms()

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

		_ = self.session.listenToEvents { event, direction, customObject in
			dlog(Self.LogTag, "event \(event.eventId ?? "<nil>") in room \(event.roomId ?? "<nil>")")

			guard let decryptionError = event.decryptionError as? NSError,
				  let peerID = peerIDFrom(serverChatUserId: event.sender) else { return }

			Task { @MainActor in
				await self.conversationDelegate?.persona(of: peerID).roomError = decryptionError
			}

			self.process(messageEvent: event)
		}

		_ = self.session.listenToEvents([.roomMember, .roomMessage]) { event, direction, state in
			switch event.eventType {
			case .roomMessage:
				self.process(messageEvent: event)
			default:
				guard direction == .forwards else { return }
				Task {
					await self.process(memberEvent: event)
				}
			}
		}
	}

	/// Observes relevant notifications in `NotificationCenter`.
	private func observeNotifications() {
		// mxRoomSummaryDidChange fires very often, but at some point the room contains a directUserId
		// mxRoomInitialSync does not fire that often and contains the directUserId only for the receiver. But that is okay, since the initiator of the room knows it anyway

		notificationObservers.append(NotificationCenter.default
			.addObserver(forName: .mxRoomInitialSync, object: nil,
						 queue: nil) { [weak self] notification in
			guard let strongSelf = self, let mxRoom = notification.object as? MXRoom else { return }

			guard let userId = mxRoom.directUserId else {
				elog("ServerChatController.observedNotifications",
					 "Found non-direct room \(mxRoom.roomId ?? "<nil>").")
				return
			}
			guard let peerID = peerIDFrom(serverChatUserId: userId) else {
				elog("ServerChatController.observedNotifications",
					 "Found room with non-PeerID \(userId).")
				return
			}

//			Task {
//				let room = await Room(mxRoom)
//				await strongSelf.listenToEvents(in: room, with: peerID)
//			}

			guard let roomId = mxRoom.roomId else {
				elog("ServerChatController.observedNotifications",
					 "Notification without roomId.")
				return
			}

			Task {
				guard let room = await strongSelf.session
					.room(withRoomId: roomId) else {
					elog("ServerChatController.observedNotifications",
						 "Notification for unknown room \(roomId).")
					return
				}
				await strongSelf.listenToEvents(in: room, with: peerID)
			}
		})
	}
}
