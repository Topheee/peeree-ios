//
//  PinMatchViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 18.09.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

class PinMatchViewController: PeerViewController {
	@IBOutlet private weak var portraitView: UIImageView!
	@IBOutlet private weak var backgroundImageView: UIImageView!
	@IBOutlet private weak var peerNameLabel: UILabel!
	
	static let StoryboardID = "PinMatch"

	override var peerID: PeerID {
		didSet { displayPeer() }
	}
	
	@IBAction func showProfile(_ sender: AnyObject) {
		cancelMatchmaking(sender)
		AppDelegate.shared.displayMessageViewController(for: peerID)
	}
	
	@IBAction func findPeer(_ sender: AnyObject) {
		cancelMatchmaking(sender)
		AppDelegate.shared.find(peerID: peerID)
	}
	
	@IBAction func cancelMatchmaking(_ sender: AnyObject) {
		presentingViewController?.dismiss(animated: true, completion: nil)
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		_ = CircleMaskView(maskedView: portraitView)
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		displayPeer()
		
		guard !UIAccessibility.isReduceTransparencyEnabled else {
			backgroundImageView.image = nil
			backgroundImageView.isHidden = true
			return
		}
		
		guard let superView = presentingViewController?.view else { return }
		
		UIGraphicsBeginImageContextWithOptions(superView.bounds.size, true, 0.0)
		
		superView.drawHierarchy(in: superView.bounds, afterScreenUpdates: false)
		
		let image = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()
		
		if #available(iOS 10.0, *) {
			image?.imageRendererFormat.opaque = true
		}
		backgroundImageView.image = image
		backgroundImageView.isOpaque = true
		backgroundImageView.isHidden = false
	}
	
	private func displayPeer() {
		peerNameLabel?.text = model.peer.info.nickname

		guard portraitView != nil else { return }
		portraitView.image = model.portraitOrPlaceholder
		portraitView.layoutIfNeeded()
		_ = CircleMaskView(maskedView: portraitView)
		if #available(iOS 11.0, *) {
			portraitView.accessibilityIgnoresInvertColors = model.picture != nil
		}
	}
}
