//
//  ServerChatPerson.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import Foundation

import DequeModule

import PeereeCore
import PeereeServerChat

/// View model of a person in the server chat module.
public final class ServerChatPerson: ObservableObject {
	init(peerID: PeerID) {
		self.peerID = peerID
	}

	public let peerID: PeerID

	@Published public var readyToChat: Bool = false

	@Published public var unreadMessages: Int = 0

	@Published public var technicalInfo: String = ""

	@Published public var roomError: Error?

	/// Chronological message thread with this peer.
	@Published public private(set) var messagesPerDay: Deque<ChatDay> = Deque()
}

extension ServerChatPerson: ServerChatPersonAspect {

	public var lastMessage: ChatMessage? {
		return messagesPerDay.last?.messages.last
	}

	/// Inserts messages into `messagesPerDay` in the correct order.
	public func insert(messages: [ChatMessage], sorted: Bool) {
		guard messages.count > 0 else { return }

		let newMessagesPerDay = sortedBuckets(of: messages, sorted: sorted)

		guard !messagesPerDay.isEmpty else {
			messagesPerDay = Deque(newMessagesPerDay)
			return
		}

		// Index in messagesPerDay
		var dayIndex = 0

		newMessagesPerDay.forEach { chatDay in
			while dayIndex < messagesPerDay.count && messagesPerDay[dayIndex] < chatDay {
				dayIndex += 1
			}

			guard dayIndex < messagesPerDay.count else {
				messagesPerDay.append(chatDay)
				return
			}

			guard messagesPerDay[dayIndex] == chatDay else {
				messagesPerDay.insert(chatDay, at: dayIndex)
				return
			}

			guard let oldLastMessage = messagesPerDay[dayIndex].messages.last,
				  let newFirstMessage = chatDay.messages.first,
				  oldLastMessage.timestamp > newFirstMessage.timestamp else {
				messagesPerDay[dayIndex].messages.append(contentsOf: chatDay.messages)
				return
			}

			guard let oldFirstMessage = messagesPerDay[dayIndex].messages.first,
				  let newLastMessage = chatDay.messages.last,
				  oldFirstMessage.timestamp < newLastMessage.timestamp else {
				messagesPerDay[dayIndex].messages.prepend(contentsOf: chatDay.messages)
				return
			}

			// https://stackoverflow.com/questions/51404787/how-to-merge-two-sorted-arrays-in-swift
			let all = self.messagesPerDay[dayIndex].messages + chatDay.messages.reversed()

			let merged = all.reduce(into: (all, Deque<ChatMessage>())) { (result, elm) in
				let first = result.0.first!
				let last = result.0.last!

				if first.timestamp < last.timestamp {
					result.0.removeFirst()
					result.1.append(first)
				} else {
					result.0.removeLast()
					result.1.append(last)
				}
			}.1

			self.messagesPerDay[dayIndex].messages = merged
		}
	}

	public func set(lastReadDate: Date) {
		let lastReadDay = DayDateComponents(from: lastReadDate)
		let (found, dayIndex) = self.messagesPerDay.binarySearch(ChatDay(day: lastReadDay, messages: Deque()))

		var unreadCount = 0

		defer {
			if unreadCount != self.unreadMessages { self.unreadMessages = unreadCount }
		}

		// full days of unread messages
		for i in (found ? dayIndex + 1 : dayIndex)..<self.messagesPerDay.count {
			unreadCount += self.messagesPerDay[i].messages.count
		}

		guard found else {
			return
		}

		let (_, msgIndex) = self.messagesPerDay[dayIndex].messages.binarySearch(lastReadDate)

		unreadCount += self.messagesPerDay[dayIndex].messages.count - msgIndex
	}
}

/// Returns sorted date-based buckets of messages.
fileprivate func sortedBuckets(of messages: [ChatMessage], sorted: Bool) -> [ChatDay] {
	return (sorted ? messages : messages.sorted { $0.timestamp < $1.timestamp }).reduce(into: [ChatDay]()) { partialResult, transcript in
		let day = DayDateComponents(from: transcript.timestamp)
		if let last = partialResult.last {
			if last.day == day {
				partialResult.indices.last.map{ partialResult[$0].messages.append(transcript) }
			} else {
				partialResult.append(ChatDay(day: day, messages: [transcript]))
			}
		} else {
			partialResult.append(ChatDay(day: day, messages: [transcript]))
		}
	}
}
