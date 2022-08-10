//
//  MessageView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 08.05.19.
//  Copyright © 2019 Kobusch. All rights reserved.
//

import UIKit

/// Custom cell for chat messages.
class MessageCell: UITableViewCell {
	
	// Background image
	@IBOutlet private weak var balloonView: UIImageView!
	// Message text string
	@IBOutlet private weak var messageLabel: UITextView!
	// these NSLayoutConstraints must not be `weak` because they get deallocated when inactive
	@IBOutlet private var ballonLeadingEqual: NSLayoutConstraint!
	@IBOutlet private var ballonTrailingEqual: NSLayoutConstraint!
	@IBOutlet private var ballonLeadingGreaterOrEqual: NSLayoutConstraint!
	@IBOutlet private var ballonTrailingGreaterOrEqual: NSLayoutConstraint!
	@IBOutlet private var messageLeading: NSLayoutConstraint!
	@IBOutlet private var messageTrailing: NSLayoutConstraint!
	
	/// Fills the cell with the contents of <code>transcript</code>.
	func set(transcript: Transcript) {
		let sent = transcript.direction == .send
		messageLabel.text = transcript.message
		ballonLeadingEqual.isActive = !sent
		ballonTrailingEqual.isActive = sent
		ballonLeadingGreaterOrEqual.isActive = sent
		ballonTrailingGreaterOrEqual.isActive = !sent
		messageLeading?.constant = sent ? 8.0 : 16.0
		messageTrailing?.constant = sent ? 16.0 : 8.0
		messageLabel?.setNeedsLayout()
		balloonView?.isHighlighted = !sent
	}
}
