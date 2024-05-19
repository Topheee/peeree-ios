//
//  MessageTableCell.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeServerChat

struct MessageTableCell: View {
	let message: ChatMessage

	var body: some View {
		HStack {
			FlipGroupView3(if: message.sent) {
				Text(message.message)
					.font(message.message.containsOnlyEmoji ? .largeTitle : .body)
					.foregroundColor(Color.white)
					.multilineTextAlignment(.leading)
					.padding(.horizontal, 20.0)
					.padding(.vertical, 4.0)
					.background(
						Image(decorative: message.sent ? "MessageBubbleSend" : "MessageBubbleReceive")
					)

				Spacer()

				Text(message.formattedTime)
					.font(.caption)
					.fontWeight(.light)
					.padding(.all, 4)
			}
		}
	}
}

#Preview {
	MessageTableCell(message: demoMessage(sent: false, message: "Hello there asdf\nadsf\nasdf\n!", timestamp:Date()))
}

#Preview {
	MessageTableCell(message: demoMessage(sent: false, message: "Hello there!", timestamp:Date()))
}

#Preview {
	MessageTableCell(message: demoMessage(sent: true, message: "General Kenobi", timestamp:Date()))
}
