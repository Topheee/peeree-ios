//
//  PinMatchViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 18.09.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit
import MultipeerConnectivity

class PinMatchViewController: UIViewController {
    @IBOutlet private weak var portraitView: UIImageView!
    @IBOutlet private weak var backgroundImageView: UIImageView!
    @IBOutlet private weak var beaconButton: UIBarButtonItem!
    @IBOutlet private weak var peerNameLabel: UILabel!
    
    static let StoryboardID = "PinMatch"
    
    var displayedPeer: PeerInfo? {
        didSet {
            portraitView.image = displayedPeer?.picture ?? UIImage(named: "PortraitUnavailable")
            peerNameLabel.text = displayedPeer?.peerName
        }
    }
    
    @IBAction func showProfile(sender: AnyObject) {
        guard let peerID = displayedPeer?.peerID else { return }
        
        cancelMatchmaking(sender)
        AppDelegate.sharedDelegate.showPeer(peerID)
    }
    
    @IBAction func findPeer(sender: AnyObject) {
        guard let peerID = displayedPeer?.peerID else { return }
        
        cancelMatchmaking(sender)
        AppDelegate.sharedDelegate.findPeer(peerID)
    }
    
    @IBAction func cancelMatchmaking(sender: AnyObject) {
        presentingViewController?.dismissViewControllerAnimated(true, completion: nil)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        portraitView.maskView = CircleMaskView(frame: portraitView.bounds)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        beaconButton.enabled = UserPeerInfo.instance.peer.iBeaconUUID != nil
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        guard let superView = presentingViewController?.view else { return }
        
        UIGraphicsBeginImageContextWithOptions(superView.bounds.size, true, 0.0)
        
        superView.drawViewHierarchyInRect(superView.bounds, afterScreenUpdates: false)
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        backgroundImageView.image = image
    }
}
