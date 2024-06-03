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
				Text(attributedString(from: message.message))
					.font(message.message.containsOnlyEmoji ? .largeTitle : .body)
					.modify {
						if #available(iOS 16, *) {
							$0.italic(message.type == .broken)
						} else {
							if message.type == .broken {
								$0.italic()
							}
						}
					}
					.textSelection(.enabled)
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

	// MARK: Private

	private static let dataDetector: NSDataDetector = {
		let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
		return try! .init(types: types.rawValue)
	}()

	// https://ivanthinking.net/thoughts/swiftui-link-phone-numbers-text-no-markdown/
	private func attributedString(from text: String) -> AttributedString {
		var attributed = AttributedString(text)
		let fullRange = NSMakeRange(0, text.count)
		let matches = Self.dataDetector.matches(in: text, options: [], range: fullRange)
		guard !matches.isEmpty else { return attributed }

		for result in matches {
			guard let range = Range<AttributedString.Index>(result.range, in: attributed) else {
				continue
			}

			switch result.resultType {
			case .phoneNumber:
				guard let phoneNumber = result.phoneNumber,
					  let url = URL(string: "tel://\(phoneNumber)") else { break }
				attributed[range].link = url

			case .link:
				guard let url = result.url else { break }
				attributed[range].link = url

			default:
				break
			}
		}

		return attributed
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
