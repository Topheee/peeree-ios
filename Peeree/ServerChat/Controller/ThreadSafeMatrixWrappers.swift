//
//  ThreadSafeMatrixWrappers.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.11.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

// The existance of this file is pure agony.

import MatrixSDK

/// This class is not completely thread-safe, but it guarantees that at least the callbacks are all called on the same queue.
class ThreadSafeCallbacksMatrixSession {
	init(session: MXSession, queue: DispatchQueue) {
		self.session = session
		self.queue = queue
	}

	private let queue: DispatchQueue

	private let session: MXSession

	var aggregations: MXAggregations? { return session.aggregations }

	var credentials: MXCredentials? { return session.credentials }

	var crypto: MXCrypto? { return session.crypto }

	var directRooms: [String : [String]]? { return session.directRooms }

	var scanManager: MXScanManager? { return session.scanManager }

	var matrixRestClient: MXRestClient? { return session.matrixRestClient }

	var store: MXStore? { return session.store }

	func deactivateAccount(withAuthParameters: [String : Any], eraseAccount: Bool, completion: @escaping (MXResponse<Void>) -> Void) {
		session.deactivateAccount(withAuthParameters: withAuthParameters, eraseAccount: eraseAccount) { response in
			self.queue.async { completion(response) }
		}
	}

	func close() {
		session.close()
	}

	func canEnableE2EByDefaultInNewRoom(withUsers: [String]!, success: @escaping (Bool) -> Void, failure: @escaping (Error?) -> Void) {
		session.canEnableE2EByDefaultInNewRoom(withUsers: withUsers) { canEnable in
			self.queue.async { success(canEnable) }
		} failure: { error in
			self.queue.async { failure(error) }
		}
	}

	func createRoom(parameters: MXRoomCreationParameters, completion: @escaping (MXResponse<MXRoom>) -> Void) {
		session.createRoom(parameters: parameters) { response in
			self.queue.async { completion(response) }
		}
	}

	func leaveRoom(_ roomId: String, completion: @escaping (MXResponse<Void>) -> Void) {
		session.leaveRoom(roomId) { response in
			self.queue.async { completion(response) }
		}
	}

	func listenToEvents(_ types: [MXEventType]? = nil, block: @escaping MXOnSessionEvent) -> Any {
		return session.listenToEvents(types) { event, direction, customObject in
			self.queue.async { block(event, direction, customObject) }
		}
	}

	func setStore(_ store: MXStore, completion: @escaping (MXResponse<Void>) -> Void) {
		session.setStore(store) { response in
			self.queue.async { completion(response) }
		}
	}

	func start(withSyncFilter: MXFilterJSONModel, completion: @escaping (MXResponse<Void>) -> Void) {
		session.start(withSyncFilter: withSyncFilter) { response in
			self.queue.async { completion(response) }
		}
	}

	func decryptEvents(_ events: [MXEvent]!, inTimeline: String, onComplete: @escaping (([MXEvent]?) -> Void)) {
		session.decryptEvents(events, inTimeline: inTimeline) { events in
			self.queue.async { onComplete(events) }
		}
	}

	func joinRoom(_ roomIdOrAlias: String, completion: @escaping (MXResponse<MXRoom>) -> Void) {
		session.joinRoom(roomIdOrAlias) { response in
			self.queue.async { completion(response) }
		}
	}

	func room(withRoomId: String) -> MXRoom! {
		return session.room(withRoomId: withRoomId)
	}

	func roomSummary(withRoomId: String) -> MXRoomSummary! {
		return session.roomSummary(withRoomId: withRoomId)
	}

	// MARK: Peeree Extensions

	func directRooms(with userId: String) -> [MXRoom] {
		return session.directRooms?[userId]?.compactMap {
			let room = self.session.room(withRoomId: $0)
			return room?.summary?.membership == .join ? room : nil
		} ?? []
	}

	func directRoomInfos(with: String,  completion: @escaping ([DirectRoomInfo]) -> Void) {
		session.directRoomInfos(with: with) { infos in
			self.queue.async { completion(infos) }
		}
	}

	func getJoinedOrInvitedRoom(with: String, bothJoined: Bool, completion: @escaping (MXRoom?) -> Void) {
		session.getJoinedOrInvitedRoom(with: with, bothJoined: bothJoined) { room in
			self.queue.async { completion(room) }
		}
	}

	func extensiveLogout(completion: @escaping (Error?) -> ()) {
		session.extensiveLogout { error in
			self.queue.async { completion(error) }
		}
	}
}
