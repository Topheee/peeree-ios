//
//  ServerChatViewModel.swift
//  Peeree
//
//  Created by Christopher Kobusch on 01.05.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import Foundation
import DequeModule
import PeereeCore

/// Holds current information of a peer's chat to be used in the UI. Thus, all variables and methods must be accessed from main thread!
public struct ServerChatViewModel {
	// MARK: - Public and Internal

	// MARK: Classes, Structs, Enums

	/// Keys in the `userInfo` dict of a notification.
	public enum NotificationInfoKey: String {
		case message
	}

	/// Names of notifications sent by `ServerChatViewModel`.
	public enum NotificationName: String {
		case messageQueued, messageSent, messageReceived, unreadMessageCountChanged

		func post(_ peerID: PeerID, message: String = "") {
			let userInfo: [AnyHashable : Any]
			if message != "" {
				userInfo = [PeerID.NotificationInfoKey : peerID, NotificationInfoKey.message.rawValue : message]
			} else {
				userInfo = [PeerID.NotificationInfoKey : peerID]
			}
			postAsNotification(object: nil, userInfo: userInfo)
		}
	}

	// MARK: Constants

	/// The PeerID identifying this view model.
	public let peerID: PeerID

	/// Chronological message thread with this peer.
	public private (set) var transcripts = [DayDateComponents : [Transcript]]()

	/// Chronological days of messages; first entry oldest.
	public private (set) var transcriptDays: Deque<DayDateComponents> = Deque()

	/// Amount of messages received, which haven't been seen yet by the user.
	public var unreadMessages: Int = 0 {
		didSet {
			guard oldValue != unreadMessages else { return }
			post(.unreadMessageCountChanged)
		}
	}

	/// Last message; if any.
	public var lastMessage: Transcript? {
		get {
			return self.transcriptDays.last.flatMap { self.transcripts[$0]?.last }
		}
	}

	/// Convenience method to retrieve the transcript as it is displayed in a table view.
	public func transcript(at: IndexPath) -> Transcript? {
		guard let messages = self.transcripts[self.transcriptDays[at.section]], at.row < messages.count else {
			assertionFailure("This code should only be called with a sensible IndexPath, not \(at).")
			return nil
		}
		return messages[at.row]
	}

	/// A message was received from this peer.
	public mutating func received(message: String, at date: Date) {
		insert(messages: [Transcript(direction: .receive, message: message, timestamp: date)], sorted: true)

		unreadMessages += 1

		post(.messageReceived, message: message)
	}

	/// A message was successfully sent to this peer.
	public mutating func didSend(message: String, at date: Date) {
		insert(messages: [Transcript(direction: .send, message: message, timestamp: date)], sorted: true)

		post(.messageSent)
	}

	/// Mass-append messages. Only fires Notifications.unreadMessageCountChanged.
	public mutating func catchUp(messages: [Transcript], sorted: Bool, unreadCount: Int) {
		insert(messages: messages, sorted: sorted)
		unreadMessages = unreadCount
		post(.unreadMessageCountChanged)
	}

	/// Removes all cached transcripts.
	public mutating func clearTranscripts() {
		transcripts.removeAll(keepingCapacity: false)
	}

	// MARK: - Private

	// MARK: Methods

	/// Inserts messages into our message list in the correct order (by time).
	private mutating func insert(messages: [Transcript], sorted: Bool) {
		guard messages.count > 0 else { return }

		sortedBuckets(of: messages, sorted: sorted).forEach { (day, dayTranscripts) in
			// https://stackoverflow.com/questions/51404787/how-to-merge-two-sorted-arrays-in-swift
			let all = self.transcripts[day, default: [Transcript]()] + dayTranscripts.reversed()

			let merged = all.reduce(into: (all, [Transcript]())) { (result, elm) in
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

			self.transcripts[day] = merged

			if day < self.transcriptDays.first ?? DayDateComponents(from: Date.distantFuture) {
				self.transcriptDays.prepend(day)
			} else if day > self.transcriptDays.last ?? DayDateComponents(from: Date.distantPast) {
				self.transcriptDays.append(day)
			} else {
				let (found, index) = self.transcriptDays.binarySearch(day)
				if !found {
					self.transcriptDays.insert(day, at: index)
				}
			}
		}
	}

	/// Shortcut.
	private func post(_ notification: NotificationName, message: String = "") {
		notification.post(peerID, message: message)
	}
}

/// Returns sorted date-based buckets of messages.
fileprivate func sortedBuckets(of messages: [Transcript], sorted: Bool) -> [(DayDateComponents, [Transcript])] {
	return (sorted ? messages : messages.sorted { $0.timestamp < $1.timestamp }).reduce(into: [(DayDateComponents, [Transcript])]()) { partialResult, transcript in
		let day = DayDateComponents(from: transcript.timestamp)
		if let last = partialResult.last {
			if last.0 == day {
				partialResult.indices.last.map{ partialResult[$0].1.append(transcript) }
			} else {
				partialResult.append((day, [transcript]))
			}
		} else {
			partialResult.append((day, [transcript]))
		}
	}
}

/// Important components for message structuring.
public struct DayDateComponents {
	let year: Int
	let month: Int8
	let dayOfMonth: Int8

	init(from date: Date) {
		dayOfMonth = Int8(Calendar.current.component(.day, from: date))
		month = Int8(Calendar.current.component(.month, from: date))
		year = Calendar.current.component(.year, from: date)
	}
}

extension DayDateComponents: Comparable {
	public static func < (lhs: DayDateComponents, rhs: DayDateComponents) -> Bool {
		if lhs.year != rhs.year {
			return lhs.year < rhs.year
		} else if lhs.month != rhs.month {
			return lhs.month < rhs.month
		} else {
			return lhs.dayOfMonth < rhs.dayOfMonth
		}
	}
}

extension DayDateComponents: Hashable {
	// Leave this to the compiler.
}

extension DayDateComponents {
	/// Conversion to Foundation's `DateComponents`.
	public var dateComponents: DateComponents {
		return DateComponents(year: self.year, month: Int(self.month), day: Int(self.dayOfMonth))
	}
}
