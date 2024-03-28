//
//  DemoServerChat.swift
//  PeereeServerChat
//
//  Created by Christopher Kobusch on 09.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import Foundation


public func demoMessage(sent: Bool, message: String, timestamp: Date) -> ChatMessage {
	return ChatMessage(eventID: UUID().uuidString, sent: sent, message: message, timestamp: timestamp)
}
