//
//  MXWrappers.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

import MatrixSDK

import PeereeCore

@ChatActor
final class Room {
	init(_ room: MXRoom) {
		self.room = room
	}

	private let room: MXRoom

	var roomId: String? { room.roomId }

	func liveTimeline() async -> EventTimeline? {
		return await withCheckedContinuation { continuation in
			room.liveTimeline { timeline in
				continuation.resume(returning: timeline.map {
					EventTimeline($0)
				})
			}
		}
	}

	func markAllAsRead() {
		room.markAllAsRead()
	}

	var summary: MXRoomSummary? {
		room.summary
	}

	var enumeratorForStoredMessages: MXEventsEnumerator? {
		room.enumeratorForStoredMessages
	}

	func sendTextMessage(_ text: String) async throws {
		_ = try await withCheckedThrowingContinuation { continuation in
			var event: MXEvent? = nil
			room.sendTextMessage(text, localEcho: &event) { response in
				continuation.resume(with: response)
			}
		}
	}
}

@ChatActor
final class EventTimeline {
	init(_ eventTimeline: MXEventTimeline) {
		self.eventTimeline = eventTimeline
	}

	private let eventTimeline: MXEventTimeline

	var timelineId: String { eventTimeline.timelineId }

	func destroy() {
		eventTimeline.destroy()
	}

	func canPaginate(_ direction: MXTimelineDirection) -> Bool {
		eventTimeline.canPaginate(direction)
	}

	func paginate(_ numItems: UInt, direction: MXTimelineDirection,
				  onlyFromStore: Bool) async throws {
		try await withCheckedThrowingContinuation { continuation in
			eventTimeline.paginate(numItems, direction: direction,
								   onlyFromStore: onlyFromStore) { response in
				continuation.resume(with: response)
			}
		}
	}
}

@ChatActor
final class Event {
	init(_ event: MXEvent) {
		self.event = event
	}

	let event: MXEvent
}

