//
//  ThreadSafeMatrixWrappers.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.11.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

// The existance of this file is pure agony.

import MatrixSDK

import PeereeCore

@ChatActor
final class ThreadSafeCallbacksMatrixSession {
	init(session: MXSession) {
		self.session = session
	}

	private let session: MXSession

	var aggregations: MXAggregations? { return session.aggregations }

	var credentials: MXCredentials? { return session.credentials }

	var crypto: MXCrypto? { return session.crypto }

	var directRooms: [String : [String]]? { return session.directRooms }

	var scanManager: MXScanManager? { return session.scanManager }

	var matrixRestClient: MXRestClient? { return session.matrixRestClient }

	var store: MXStore? { return session.store }

	func deactivateAccount(withAuthParameters: [String : Any],
						   eraseAccount: Bool) async throws {
		let response = await withCheckedContinuation { continuation in
			self.session.deactivateAccount(
				withAuthParameters: withAuthParameters,
				eraseAccount: eraseAccount) { response in
				continuation.resume(returning: response)
			}
		}

		if case .failure(let error) = response { throw error }
	}

	func close() {
		session.close()
	}

	func canEnableE2EByDefaultInNewRoom(withUsers users: [String]!) async throws -> Bool {
		return try await withCheckedThrowingContinuation { continuation in
			self.session.canEnableE2EByDefaultInNewRoom(withUsers: users) { canEnable in
				continuation.resume(returning: canEnable)
			} failure: { error in
				continuation.resume(throwing: error ?? unexpectedNilError())
			}
		}
	}

	func createRoom(parameters: MXRoomCreationParameters) async throws -> Room {
		return try await withCheckedThrowingContinuation { continuation in
			self.session.createRoom(parameters: parameters) { response in
				continuation.resume(with: response.map{ mxRoom in
					Room(mxRoom)
				})
			}
		}
	}

	func leaveRoom(_ roomId: String) async throws {
		return try await withCheckedThrowingContinuation { continuation in
			self.session.leaveRoom(roomId) { response in
				continuation.resume(with: response)
			}
		}
	}

	func listenToEvents(_ types: [MXEventType]? = nil, block: @escaping MXOnSessionEvent) -> Any {
		// TODO: convert to async sequence
		return session.listenToEvents(types) { event, direction, customObject in
			block(event, direction, customObject)
		}
	}

	func setStore(_ store: MXStore) async throws {
		return try await withCheckedThrowingContinuation { continuation in
			self.session.setStore(store) { response in
				continuation.resume(with: response)
			}
		}
	}

	func start(withSyncFilter: MXFilterJSONModel) async throws {
		return try await withCheckedThrowingContinuation { continuation in
			self.session.start(withSyncFilter: withSyncFilter) { response in
				continuation.resume(with: response)
			}
		}
	}

	func decryptEvents(_ events: [Event],
					   inTimeline: String) async -> [Event]? {
		return await withCheckedContinuation { continuation in
			self.session.decryptEvents(events.map { $0.event },
									   inTimeline: inTimeline) { mxEvents in
				guard let mxEvents else {
					continuation.resume(returning: nil)
					return
				}

				continuation.resume(returning: mxEvents.map { Event($0) })
			}
		}
	}

	func joinRoom(_ roomIdOrAlias: String) async throws -> Room {
		return try await withCheckedThrowingContinuation { continuation in
			self.session.joinRoom(roomIdOrAlias) { response in
				continuation.resume(with: response.map{ mxRoom in
					Room(mxRoom)
				})
			}
		}
	}

	func room(withRoomId roomId: String) -> Room? {
		return session.room(withRoomId: roomId).map { Room($0) }
	}

	func roomSummary(withRoomId: String) -> MXRoomSummary! {
		return session.roomSummary(withRoomId: withRoomId)
	}

	// MARK: Peeree Extensions

	func directRooms(with userId: String) -> [Room] {
		return session.directRooms?[userId]?.compactMap {
			let room = self.session.room(withRoomId: $0)
			return room?.summary?.membership == .join ?
				room.map { Room($0) } : nil
		} ?? []
	}

	func directRoomInfos(with: String) async -> [DirectRoomInfo] {
		return await withCheckedContinuation { continuation in
			self.session.directRoomInfos(with: with) { infos in
				continuation.resume(returning: infos)
			}
		}
	}

	func getJoinedOrInvitedRoom(with: String, bothJoined: Bool) async -> Room? {
		return await withCheckedContinuation { continuation in
			self.session.getJoinedOrInvitedRoom(with: with, bothJoined: bothJoined) { room in
				continuation.resume(returning: room.map { Room($0) })
			}
		}
	}

	func extensiveLogout() async throws {
		return try await withCheckedThrowingContinuation { continuation in
			self.session.extensiveLogout { error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: ())
				}
			}
		}
	}

	func clearAllData() {
		self.session.clearAllData()
	}
}
