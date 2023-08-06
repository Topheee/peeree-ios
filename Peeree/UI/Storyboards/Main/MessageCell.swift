//
//  MessageView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 08.05.19.
//  Copyright © 2019 Kobusch. All rights reserved.
//

import UIKit
import PeereeServerChat

private let timestampFormatter: DateFormatter = {
	let formatter = DateFormatter()
	formatter.dateStyle = .none
	formatter.timeStyle = .short
	return formatter
}()

@MainActor
protocol MessageCell {
	func set(transcript: Transcript)
}

/// Custom cell for chat messages.
final class SendMessageCell: UITableViewCell, MessageCell {
	/// Message text string.
	@IBOutlet private weak var messageLabel: UITextView!

	/// Time string.
	@IBOutlet private weak var timeLabel: UILabel!

	/// Fills the cell with the contents of <code>transcript</code>.
	func set(transcript: Transcript) {
		messageLabel?.text = transcript.message
		messageLabel?.setNeedsLayout()
		if #available(iOS 15.0, *) {
			timeLabel?.text = transcript.timestamp.formatted(date: .omitted, time: .shortened)
		} else {
			timeLabel?.text = timestampFormatter.string(from: transcript.timestamp)
		}
	}
}

/// Custom cell for chat messages.
final class ReceiveMessageCell: UITableViewCell, MessageCell {
	/// Message text string.
	@IBOutlet private weak var messageLabel: UITextView!

	/// Time string.
	@IBOutlet private weak var timeLabel: UILabel!

	/// Fills the cell with the contents of <code>transcript</code>.
	func set(transcript: Transcript) {
		messageLabel?.text = transcript.message
		messageLabel?.setNeedsLayout()
		if #available(iOS 15.0, *) {
			timeLabel?.text = transcript.timestamp.formatted(date: .omitted, time: .shortened)
		} else {
			timeLabel?.text = timestampFormatter.string(from: transcript.timestamp)
		}
	}
}
