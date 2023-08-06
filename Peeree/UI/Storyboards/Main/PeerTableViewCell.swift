//
//  PeerTableViewCell.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.04.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import UIKit
import PeereeCore
import PeereeDiscovery

final class PeerTableViewCell: UITableViewCell {
	@IBOutlet private weak var portraitImageView: RoundedImageView!
	@IBOutlet private weak var nameLabel: UILabel!
	@IBOutlet private weak var lastSeenLabel: UILabel!
	@IBOutlet private weak var ageTagView: RoundedRectView!
	@IBOutlet private weak var ageLabel: UILabel!
	@IBOutlet private weak var genderLabel: UILabel!
	@IBOutlet private weak var pinImageView: UIImageView!

	func fill(with peerModel: PeerViewModel, pinState: PinState) {
		let peerInfo = peerModel.info
		portraitImageView.image = peerModel.portraitOrPlaceholder.roundedCropped(cropRect: portraitImageView.bounds, backgroundColor: AppTheme.backgroundColor)
		nameLabel.text = peerInfo.nickname
		lastSeenLabel.text = peerModel.lastSeenText
		ageTagView.isHidden = peerInfo.age == nil
		ageTagView.setNeedsDisplay()
		ageLabel.text = "\(peerInfo.age ?? 0)"
		genderLabel.text = peerInfo.gender.localizedRawValue
		pinImageView.isHidden = !pinState.isPinned
		pinImageView.image = pinState == .pinMatch ? #imageLiteral(resourceName: "PinTemplatePressed") : #imageLiteral(resourceName: "PinTemplate")
	}
}
