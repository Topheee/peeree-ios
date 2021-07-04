//
//  PeerTableViewCell.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.04.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import UIKit

final class PeerTableViewCell: UITableViewCell {
	@IBOutlet private weak var portraitImageView: RoundedImageView!
	@IBOutlet private weak var nameLabel: UILabel!
	@IBOutlet private weak var ageTagView: RoundedRectView!
	@IBOutlet private weak var genderTagView: RoundedRectView!
	@IBOutlet private weak var ageLabel: UILabel!
	@IBOutlet private weak var genderLabel: UILabel!

	func fill(with peerManager: PeerManager) {
		guard let peerInfo = peerManager.peerInfo else { return }
		portraitImageView.image = peerManager.pictureClassification == .none ? peerManager.picture ?? (peerInfo.hasPicture ? #imageLiteral(resourceName: "PortraitPlaceholder") : #imageLiteral(resourceName: "PortraitUnavailable")) : #imageLiteral(resourceName: "ObjectionablePortraitPlaceholder")
		portraitImageView.image = portraitImageView.image?.roundedCropped(cropRect: portraitImageView.bounds, backgroundColor: AppTheme.backgroundColor)
		nameLabel.text = peerInfo.nickname
		ageTagView.isHidden = peerInfo.age == nil
		ageTagView.setNeedsDisplay()
		ageLabel.text = "\(peerInfo.age ?? 0)"
		genderLabel.text = peerInfo.gender.localizedRawValue
	}
}
