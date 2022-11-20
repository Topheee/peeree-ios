//
//  MXSessionExtensions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 29.05.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import MatrixSDK

extension MXSession {

	// MARK: Methods

	/// Logs outs the session as well as cleans up more local stuff.
	func extensiveLogout(_ completion: @escaping (Swift.Error?) -> ()) {
		logout { response in
			if response.isFailure {
				elog("Failed to log out successfully - still cleaning up session data.")
			}
			// *** roughly based on MXKAccount.closeSession(true) ***
			self.scanManager?.deleteAllAntivirusScans()
			self.aggregations?.resetData()
			self.close()
			self.store?.deleteAllData()
			completion(response.error)
		}
	}

	/// Fetches direct rooms recursively.
	private func directRoomInfosRecursive(with userId: String, directJoinedRooms: [MXRoom], idx: Int, infos: [DirectRoomInfo], _ completion: @escaping ([DirectRoomInfo]) -> Void) {
		guard idx < directJoinedRooms.count else {
			completion(infos)
			return
		}

		guard directJoinedRooms[idx].summary?.membership == .join else {
			let new = DirectRoomInfo(room: directJoinedRooms[idx], ourMembership: directJoinedRooms[idx].summary?.membership ?? .invite, theirMembership: .join)
			self.directRoomInfosRecursive(with: userId, directJoinedRooms: directJoinedRooms, idx: idx + 1, infos: infos + [new], completion)
			return
		}

		directJoinedRooms[idx].members { response in
			switch response {
			case .success(let members):
				guard let members = members?.members else {
					elog("members is nil")
					break
				}

				guard let theirMember = members.first(where: { $0.userId == userId}),
					  let ourMember = members.first(where: { $0.userId == self.myUserId}) else {
					elog("Cannot find our or their member.")
					break
				}

				let new = DirectRoomInfo(room: directJoinedRooms[idx], ourMembership: ourMember.membership, theirMembership: theirMember.membership)
				self.directRoomInfosRecursive(with: userId, directJoinedRooms: directJoinedRooms, idx: idx + 1, infos: infos + [new], completion)

			case .failure(let error):
				elog("Couldn't fetch members for room \(directJoinedRooms[idx].roomId ?? "<nil>"): \(error)")
				self.directRoomInfosRecursive(with: userId, directJoinedRooms: directJoinedRooms, idx: idx + 1, infos: infos, completion)
			}

		}
	}

	/// Fetches direct rooms; safer than the MatrixSDK implementation.
	func directRoomInfos(with userId: String, _ completion: @escaping ([DirectRoomInfo]) -> Void) {
		guard let directRooms = self.directRooms?[userId] else {
			completion([])
			return
		}

		var directNonLeaveRooms: [MXRoom] = directRooms.compactMap { roomId in
			guard let room = self.room(withRoomId: roomId),
				  let summary = room.summary,
				  room.directUserId == userId,
				  summary.membership != .leave && summary.membership != .ban else { return nil }

			return room
		}

		directNonLeaveRooms.append(contentsOf: self.rooms.filter { room in
			guard let summary = room.summary else { return false }

			return room.directUserId == userId && summary.membership != .leave && summary.membership != .ban
		})

		let directJoinedRooms = Set<MXRoom>(directNonLeaveRooms)

		// always leave all rooms where the other one already left
		directRoomInfosRecursive(with: userId, directJoinedRooms: directJoinedRooms.map { $0 }, idx: 0, infos: []) { infos in
			completion(infos)
		}
	}

	/// Recursively checks whether the room at `idx` in `rooms` has both members joined (if `bothJoined` is `true`) or at least invited (if `bothJoined` is `false`).
	private func testRoom(idx: Int, of rooms: [MXRoom], with peerUserId: String, bothJoined: Bool, _ completion: @escaping (MXRoom?) -> Void) {
		guard idx < rooms.count else {
			completion(nil)
			return
		}

		let room = rooms[idx]

		guard let roomSummary = room.summary else {
			testRoom(idx: idx + 1, of: rooms, with: peerUserId, bothJoined: bothJoined, completion)
			return
		}

		guard bothJoined else {
			if roomSummary.membership == .join || roomSummary.membership == .invite {
				completion(room)
			} else {
				testRoom(idx: idx + 1, of: rooms, with: peerUserId, bothJoined: bothJoined, completion)
			}
			return
		}

		guard roomSummary.membership == .join else {
			// we cannot ask for the room members at this state, since we are not yet a member ourselves (not joined)
			// and we cannot chat as long as we are not joined anyway
			testRoom(idx: idx + 1, of: rooms, with: peerUserId, bothJoined: bothJoined, completion)
			return
		}

		room.members { membersResponse in
			guard let _members = membersResponse.value, let members = _members,
				  let theirMember = members.members.first(where: { $0.userId == peerUserId}) else {
				flog("We are not a member of room \(room).")
				self.testRoom(idx: idx + 1, of: rooms, with: peerUserId, bothJoined: bothJoined, completion)
				return
			}

			if theirMember.membership == .join || (!bothJoined && theirMember.membership == .invite) {
				completion(room)
			} else {
				self.testRoom(idx: idx + 1, of: rooms, with: peerUserId, bothJoined: bothJoined, completion)
			}
		}
	}

	/// Retrieves an already joined or invited room with `userId`.
	func getJoinedOrInvitedRoom(with userId: String, bothJoined: Bool, _ completion: @escaping (MXRoom?) -> Void) {
		// unfortunately, due shitty circumstance we may have several direct rooms with a person and MXSession.directJoinedRoom does not always return a room where both joined, so we cannot use it here
		guard let directRooms = self.directRooms?[userId]?.compactMap({ self.room(withRoomId: $0) }) else {
			completion(nil)
			return
		}

		testRoom(idx: 0, of: directRooms, with: userId, bothJoined: bothJoined, completion)
	}
}

/// Combines scattered information on a room; currently only memberships.
struct DirectRoomInfo {
	/// The Matrix room.
	let room: MXRoom

	/// The membership status of the local user.
	let ourMembership: MXMembership

	/// The membership status of the remote user.
	let theirMembership: MXMembership
}
