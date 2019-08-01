//
//  MessageView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 08.05.19.
//  Copyright © 2019 Kobusch. All rights reserved.
//

import UIKit

// Constants for view sizing and alignment
//let MESSAGE_FONT_SIZE: CGFloat =       (17.0)
//let NAME_FONT_SIZE: CGFloat =          (10.0)
//let BUFFER_WHITE_SPACE: CGFloat =      (14.0)
//let DETAIL_TEXT_LABEL_WIDTH = (220.0)
//let NAME_OFFSET_ADJUST: CGFloat =      (4.0)
//
//let BALLOON_INSET_TOP: CGFloat =    (30 / 2)
//let BALLOON_INSET_LEFT: CGFloat =   (36 / 2)
//let BALLOON_INSET_BOTTOM: CGFloat = (30 / 2)
//let BALLOON_INSET_RIGHT: CGFloat =  (46 / 2)
//
//let BALLOON_INSET_WIDTH: CGFloat = (BALLOON_INSET_LEFT + BALLOON_INSET_RIGHT)
//let BALLOON_INSET_HEIGHT: CGFloat = (BALLOON_INSET_TOP + BALLOON_INSET_BOTTOM)
//
//let BALLOON_MIDDLE_WIDTH: CGFloat = (30 / 2)
//let BALLOON_MIDDLE_HEIGHT: CGFloat = (6 / 2)
//
//let BALLOON_MIN_HEIGHT: CGFloat = (BALLOON_INSET_HEIGHT + BALLOON_MIDDLE_HEIGHT)
//
//let BALLOON_HEIGHT_PADDING: CGFloat = (10)
//let BALLOON_WIDTH_PADDING: CGFloat = (30)

class MessageCell: UITableViewCell {
	
	// Background image
	@IBOutlet private weak var balloonView: UIImageView!
	// Message text string
	@IBOutlet private weak var messageLabel: UILabel!
	@IBOutlet private weak var ballonLeading: NSLayoutConstraint!
	@IBOutlet private weak var ballonTrailing: NSLayoutConstraint!
	@IBOutlet private weak var messageLeading: NSLayoutConstraint!
	@IBOutlet private weak var messageTrailing: NSLayoutConstraint!
	
	func set(transcript: Transcript) {
		let sent = transcript.direction == .send
		messageLabel.text = transcript.message
		ballonLeading.constant = sent ? 20.0 : 8.0
		ballonTrailing.constant = sent ? 8.0 : 20.0
		messageLeading.constant = sent ? 8.0 : 24.0
		messageTrailing.constant = sent ? 24.0 : 8.0
		messageLabel.setNeedsLayout()
		balloonView.isHighlighted = !sent
	}
}

//class MessageView: UIView {
//	// Cache the background images and stretchable insets
//	static let balloonImageLeft: UIImage = #imageLiteral(resourceName: "MessageBubbleOpposite")
//	static let balloonImageRight: UIImage = #imageLiteral(resourceName: "MessageBubble")
//	let balloonInsetsLeft = UIEdgeInsets(top: BALLOON_INSET_TOP, left: BALLOON_INSET_RIGHT, bottom: BALLOON_INSET_BOTTOM, right: BALLOON_INSET_LEFT)
//	let balloonInsetsRight = UIEdgeInsets(top: BALLOON_INSET_TOP, left: BALLOON_INSET_LEFT, bottom: BALLOON_INSET_BOTTOM, right: BALLOON_INSET_RIGHT)
//
//	// Method for setting the transcript object which is used to build this view instance.
//	func set(transcript: Transcript) {
//		// Set the message text
//		let messageText = transcript.message
//		messageLabel.text = messageText
//
//		// Compute message size and frames
//		let labelSize = MessageCell.labelSize(for: messageText, fontSize:MESSAGE_FONT_SIZE)
//		let balloonSize = MessageCell.balloonSize(for: labelSize)
//
//		// Compute the X,Y origin offsets
//		var xOffsetLabel: CGFloat
//		var xOffsetBalloon: CGFloat
//		var yOffset: CGFloat
//
//		if (.send == transcript.direction) {
//			// Sent messages appear on the right of the view
//			xOffsetLabel = 320 - labelSize.width - (BALLOON_WIDTH_PADDING / 2) - 3
//			xOffsetBalloon = 320 - balloonSize.width
//			yOffset = BUFFER_WHITE_SPACE / 2
//			// Set text color
//			messageLabel.textColor = UIColor.white
//			// Set resizeable image
//			balloonView.image = MessageCell.balloonImageRight.resizableImage(withCapInsets: balloonInsetsRight)
//		}
//		else {
//			// Received messages appear on left of view with additional display name label
//			xOffsetBalloon = 0
//			xOffsetLabel = (BALLOON_WIDTH_PADDING / 2) + 3
//			yOffset = (BUFFER_WHITE_SPACE / 2) //+ nameSize.height - NAME_OFFSET_ADJUST
//			// Set text color
//			messageLabel.textColor = UIColor.darkText
//			// Set resizeable image
//			balloonView.image = MessageCell.balloonImageLeft.resizableImage(withCapInsets: balloonInsetsLeft)
//		}
//
//		// Set the dynamic frames
//		messageLabel.frame = CGRect(x: xOffsetLabel, y: yOffset + 5, width: labelSize.width, height: labelSize.height)
//		balloonView.frame = CGRect(x: xOffsetBalloon, y: yOffset, width: balloonSize.width, height: balloonSize.height)
//	}
//
//	// MARK: - Class Methods for Computing Sizes based on Strings
//
//	static func viewHeight(for transcript: Transcript) -> CGFloat {
//		let labelHeight = MessageCell.balloonSize(for: MessageCell.labelSize(for: transcript.message, fontSize:MESSAGE_FONT_SIZE)).height
//		return labelHeight + BUFFER_WHITE_SPACE
//	}
//
//	static func labelSize(for string: String, fontSize: CGFloat) -> CGSize {
//		return string.boundingRect(with: CGSize(width: DETAIL_TEXT_LABEL_WIDTH, height: 2000.0), options:.usesLineFragmentOrigin,
//								   attributes:[NSAttributedString.Key.font : UIFont.systemFont(ofSize: fontSize)], context:nil).size
//	}
//
//	static func balloonSize(for labelSize: CGSize) -> CGSize {
//		return CGSize(width: labelSize.width + BALLOON_WIDTH_PADDING,
//					  height: labelSize.height < BALLOON_INSET_HEIGHT ? BALLOON_MIN_HEIGHT : labelSize.height + BALLOON_HEIGHT_PADDING)
//	}
//
//}
