//
//  PersonDetailViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import MultipeerConnectivity

class PersonDetailViewController: UIViewController {
	@IBOutlet var scrollView: UIScrollView!
	@IBOutlet var contentView: UIView!
	
	@IBOutlet var portraitImageView: UIImageView!
	@IBOutlet var ageGenderLabel: UILabel!
	@IBOutlet var stateLabel: UILabel!
	
	@IBAction func pinPeer(sender: UIButton) {
		// TODO pin this peer
	}
	
	var displayedPeer: MCPeerID!
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		scrollView.layoutIfNeeded()
		scrollView.contentSize = contentView.bounds.size
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		portraitImageView.maskView = CircleMaskView(forView: portraitImageView)
	}
	
	override func viewWillAppear(animated: Bool) {
		super.viewDidAppear(animated)
		if displayedPeer == nil {
			// rewind to previous view controller
			return
		}
		if let localPeerInfo = RemotePeerManager.sharedManager.getPeerInfo(forPeer: displayedPeer, download: true) {
            navigationItem.title = localPeerInfo.fullName
            //TODO localization
			ageGenderLabel.text = "\(localPeerInfo.age) years old, \(localPeerInfo.hasVagina ? "female" : "male")"
			stateLabel.text = SerializablePeerInfo.possibleStatuses[localPeerInfo.statusID]
//			if localPeerInfo.hasPicture {
//				if localPeerInfo.isPictureLoading {
//					// TODO show waiting indicator
//				} else {
					portraitImageView.image = localPeerInfo.picture
//				}
//			} else {
//				// TODO show now picture icon
//			}
		}
	}
}
