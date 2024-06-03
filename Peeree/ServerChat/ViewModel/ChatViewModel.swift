//
//  ChatViewModel.swift
//  PeereeServerChat
//
//  Created by Christopher Kobusch on 17.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import Foundation

import DequeModule

import PeereeCore

private let timestampFormatter: DateFormatter = {
	let formatter = DateFormatter()
	formatter.dateStyle = .none
	formatter.timeStyle = .short
	return formatter
}()

private let headerFormatter: DateFormatter = {
	let formatter = DateFormatter()
	formatter.dateStyle = .full
	formatter.timeStyle = .none
	return formatter
}()

public enum ChatMessageType {
	case sent, received, broken, pending
}

public struct ChatMessage {
	public let eventID: String

	public let type: ChatMessageType

	public let message: String

	public let timestamp: Date
}

extension ChatMessage {
	public var sent: Bool {
		return type == .sent || type == .pending
	}
}

extension ChatMessage: Identifiable {

	public var id: String { return eventID }
}

extension ChatMessage: GenComparable {
	public typealias Other = Date

	public static func == (lhs: ChatMessage, rhs: Date) -> Bool {
		return lhs.timestamp == rhs
	}

	public static func < (lhs: ChatMessage, rhs: Date) -> Bool {
		return lhs.timestamp < rhs
	}
}

extension ChatMessage {

	public var formattedTime: String {
		if #available(iOS 15.0, *) {
			return self.timestamp.formatted(date: .omitted, time: .shortened)
		} else {
			return timestampFormatter.string(from: self.timestamp)
		}
	}
}

public struct ChatDay {

	public let day: DayDateComponents

	public var messages: Deque<ChatMessage>

	public init(day: DayDateComponents, messages: Deque<ChatMessage>) {
		self.day = day
		self.messages = messages
	}
}

extension ChatDay: Identifiable {

	public var id: DayDateComponents { return day }
}

extension ChatDay: Comparable {
	public static func == (lhs: ChatDay, rhs: ChatDay) -> Bool {
		return lhs.day == rhs.day
	}
	
	public static func < (lhs: ChatDay, rhs: ChatDay) -> Bool {
		return lhs.day < rhs.day
	}
}

extension ChatDay {

	public var title: String {
		return headerFormatter.string(from: Calendar.current.date(from: day.dateComponents) ?? Date())
	}
}


/// Important components for message structuring.
public struct DayDateComponents {
	let year: Int
	let month: Int8
	let dayOfMonth: Int8

	public init(from date: Date) {
		let c = Calendar.current
		dayOfMonth = Int8(c.component(.day, from: date))
		month = Int8(c.component(.month, from: date))
		year = c.component(.year, from: date)
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
