//
//  ServerChatPersonAspect.swift
//  PeereeServerChat
//
//  Created by Christopher Kobusch on 16.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import PeereeCore

@MainActor
public protocol ServerChatPersonAspect: PersonAspect {

	var readyToChat: Bool { get set }

	var unreadMessages: Int { get set }

	/// Inserts messages into `messagesPerDay` in the correct order.
	func insert(messages: [ChatMessage], sorted: Bool)

	func set(lastReadDate: Date)
}
