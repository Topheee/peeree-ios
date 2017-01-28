//
//  PinMatchViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 18.09.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

class PinMatchViewController: UIViewController {
    @IBOutlet private weak var portraitView: UIImageView!
    @IBOutlet private weak var backgroundImageView: UIImageView!
    @IBOutlet private weak var beaconButton: UIBarButtonItem!
    @IBOutlet private weak var peerNameLabel: UILabel!
    
    static let StoryboardID = "PinMatch"
    
    var displayedPeer: PeerInfo? {
        didSet {
            displayPeer()
        }
    }
    
    @IBAction func showProfile(_ sender: AnyObject) {
        guard let peerID = displayedPeer?.peerID else { return }
        
        cancelMatchmaking(sender)
        AppDelegate.shared.show(peer: peerID)
    }
    
    @IBAction func findPeer(_ sender: AnyObject) {
        guard let peerID = displayedPeer?.peerID else { return }
        
        cancelMatchmaking(sender)
        AppDelegate.shared.find(peer: peerID)
    }
    
    @IBAction func cancelMatchmaking(_ sender: AnyObject) {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        _ = CircleMaskView(maskedView: portraitView)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        beaconButton.isEnabled = UserPeerInfo.instance.peer.iBeaconUUID != nil
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        displayPeer()
        
        guard !UIAccessibilityIsReduceTransparencyEnabled() else {
            backgroundImageView.image = nil
            backgroundImageView.isHidden = true
            return
        }
        
        guard let superView = presentingViewController?.view else { return }
        
        UIGraphicsBeginImageContextWithOptions(superView.bounds.size, true, 0.0)
        
        superView.drawHierarchy(in: superView.bounds, afterScreenUpdates: false)
        
//        let image = autoreleasepool {
//            return UIGraphicsGetImageFromCurrentImageContext()
//        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        if #available(iOS 10.0, *) {
            image?.imageRendererFormat.opaque = true
            backgroundImageView.image = image
        } else {
            backgroundImageView.image = image
        }
        backgroundImageView.isOpaque = true
        // TEST is the image and the image view really opaque?
        backgroundImageView.isHidden = false
    }
    
    private func displayPeer() {
        peerNameLabel?.text = displayedPeer?.nickname
        
        guard portraitView != nil else { return }
        portraitView.image = displayedPeer?.picture ?? UIImage(named: "PortraitUnavailable")
        _ = CircleMaskView(maskedView: portraitView)
    }
}
