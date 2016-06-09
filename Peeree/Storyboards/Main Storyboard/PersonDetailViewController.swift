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
	@IBOutlet private var portraitImageView: UIImageView!
	@IBOutlet private var ageGenderLabel: UILabel!
	@IBOutlet private var stateLabel: UILabel!
	
	@IBAction func pinPeer(sender: UIButton) {
		// TODO pin this peer
	}
	
	var displayedPeer: MCPeerID?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		portraitImageView.maskView = CircleMaskView(forView: portraitImageView)
	}
	
	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		guard let peer = displayedPeer else { return }
        var userPeerInfo: LocalPeerInfo? = nil
        if UserPeerInfo.instance.peerID == displayedPeer {
            userPeerInfo = UserPeerInfo.instance
        }
		guard let localPeerInfo = RemotePeerManager.sharedManager.getPeerInfo(forPeer: peer, download: true) ?? userPeerInfo else { return }
        
        navigationItem.title = localPeerInfo.peerName
        
        //TODO localization
        ageGenderLabel.text = "\(localPeerInfo.age) years old, \(localPeerInfo.hasVagina ? "female" : "male")"
        stateLabel.text = SerializablePeerInfo.possibleStatuses[localPeerInfo.statusID]
		if localPeerInfo.hasPicture {
			if localPeerInfo.isPictureLoading {
				// TODO show waiting indicator
			} else {
                portraitImageView.image = localPeerInfo.picture
			}
		} else {
			// TODO show now picture icon
		}
	}
}
