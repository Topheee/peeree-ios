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

	override var peerManager: PeerManager! {
		didSet { displayPeer() }
	}
	
	@IBAction func showProfile(_ sender: AnyObject) {
		cancelMatchmaking(sender)
		AppDelegate.shared.displayMessageViewController(for: peerManager.peerID)
	}
	
	@IBAction func findPeer(_ sender: AnyObject) {
		guard let peer = peerManager.peerInfo else { return }

		cancelMatchmaking(sender)
		AppDelegate.shared.find(peer: peer)
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
		guard let manager = peerManager, let peer = manager.peerInfo else { return }
		peerNameLabel?.text = peer.nickname
		
		guard portraitView != nil else { return }
		portraitView.image = manager.picture ?? #imageLiteral(resourceName: "PortraitUnavailable")
		portraitView.layoutIfNeeded()
		_ = CircleMaskView(maskedView: portraitView)
		if #available(iOS 11.0, *) {
			portraitView.accessibilityIgnoresInvertColors = manager.picture != nil
		}
	}
}
