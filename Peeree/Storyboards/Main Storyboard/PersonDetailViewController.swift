//
//  PersonDetailViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import MultipeerConnectivity

final class PersonDetailViewController: UIViewController {
	@IBOutlet private weak var portraitImageView: UIImageView!
	@IBOutlet private weak var ageGenderLabel: UILabel!
	@IBOutlet private weak var stateLabel: UILabel!
    @IBOutlet private weak var downloadIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var pinButton: UIButton!
    @IBOutlet private weak var pictureDownloadIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var traitsButton: UIButton!
    @IBOutlet private weak var gradientView: UIImageView!
    @IBOutlet private weak var pinIndicator: UIActivityIndicatorView!
    
    private static let unwindSegueID = "unwindToBrowseViewController"
    
    private var notificationObservers: [AnyObject] = []
    
    private var displayedPeerInfo: PeerInfo?
    
    var displayedPeerID: MCPeerID?
    
    @IBAction func unwindToBrowseViewController(segue: UIStoryboardSegue) {
        
    }
    
	@IBAction func pinPeer(sender: UIButton) {
        guard let peer = displayedPeerInfo else { return }
        guard !peer.pinned else { return }
        
        pinIndicator.hidden = false
        RemotePeerManager.sharedManager.pinPeer(peer.peerID)
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if let charTraitVC = segue.destinationViewController as?
            CharacterTraitViewController {
            charTraitVC.characterTraits = displayedPeerInfo?.characterTraits
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        pinButton.setImage(UIImage(named: "PinTemplatePressed"), forState: [.Disabled, .Selected])
    }
    
	override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        guard displayedPeerID != nil else { assertionFailure(); return }
        
        navigationItem.title = displayedPeerID!.displayName
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.RemotePeerAppeared.addObserver { (notification) in
            if let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID {
                self.remotePeerAppeared(peerID)
            }
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.RemotePeerDisappeared.addObserver { (notification) in
            if let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID {
                self.remotePeerDisappeared(peerID)
            }
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.PeerInfoLoaded.addObserver { (notification) in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }
            guard self.displayedPeerID != nil && self.displayedPeerID! == peerID else { return }
            
            self.displayedPeerInfo = RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID)
            self.displayPeerInfo()
            self.displayPeerInfoDownloadState()
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.PictureLoaded.addObserver { (notification) in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }
            guard self.displayedPeerID != nil && self.displayedPeerID! == peerID else { return }
            
            self.displayedPeerInfo = RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID)
            self.displayImageState()
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.PinMatch.addObserver { (notification) in
            self.gradientView.hidden = self.displayedPeerInfo?.pinMatched ?? true
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.PeerInfoLoadFailed.addObserver { (notification) in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }
            guard self.displayedPeerID != nil && self.displayedPeerID! == peerID else { return }
            
            self.performSegueWithIdentifier(PersonDetailViewController.unwindSegueID, sender: self)
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.PictureLoadFailed.addObserver { (notification) in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }
            guard self.displayedPeerID != nil && self.displayedPeerID! == peerID else { return }
            
            self.displayImageState()
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.Pinned.addObserver { (notification) in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }
            guard self.displayedPeerID != nil && self.displayedPeerID! == peerID else { return }
            
            self.pinButton.selected = true
            self.pinIndicator.hidden = true
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.PinFailed.addObserver { (notification) in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }
            guard self.displayedPeerID != nil && self.displayedPeerID! == peerID else { return }
            
            self.pinButton.selected = false
            self.pinIndicator.hidden = true
        })
        
        if displayedPeerID! != UserPeerInfo.instance.peer.peerID {
            displayedPeerInfo = RemotePeerManager.sharedManager.getPeerInfo(forPeer: displayedPeerID!, download: true)
        } else {
            displayedPeerInfo = UserPeerInfo.instance.peer
        }
        setupTitle()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        displayPeerInfoDownloadState()
        displayPeerInfo()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        portraitImageView.maskView = CircleMaskView(forView: portraitImageView)
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        for observer in notificationObservers {
            NSNotificationCenter.defaultCenter().removeObserver(observer)
        }
    }
    
    // MARK: Private methods
    
    private func remotePeerAppeared(peer: MCPeerID) {
        if displayedPeerID != nil && displayedPeerID! == peer {
            setupTitle()
            enablePinButton()
        }
    }
    
    private func remotePeerDisappeared(peer: MCPeerID) {
        if displayedPeerID != nil && displayedPeerID! == peer {
            setupTitle()
            enablePinButton()
        }
    }
    
    private func pictureLoaded(peerInfo: PeerInfo) {
        if displayedPeerID != nil && displayedPeerID! == peerInfo.peerID {
            displayedPeerInfo = peerInfo
            displayPeerInfo()
            displayPeerInfoDownloadState()
        }
    }
    
    private func displayPeerInfo() {
        guard let peerInfo = displayedPeerInfo else { return }
        
        let ageGenderFormat = NSLocalizedString("%d years old, %@", comment: "Text describing the peers age and gender.")
        ageGenderLabel.text = String(format: ageGenderFormat, peerInfo.age, peerInfo.gender.localizedRawValue)
        stateLabel.text = peerInfo.relationshipStatus.localizedRawValue
        RemotePeerManager.sharedManager.loadPicture(peerInfo)
        displayImageState()
        enablePinButton()
        pinButton.selected = peerInfo.pinned
        gradientView.hidden = !(peerInfo.pinMatched || displayedPeerID! == UserPeerInfo.instance.peer.peerID)
        UIView.animateWithDuration(1.5, delay: 0.0, usingSpringWithDamping: 2.0, initialSpringVelocity: 1.0, options: [.Repeat, .Autoreverse], animations: {
            self.gradientView.alpha = 0.0
        }, completion: nil)
    }
    
    private func displayPeerInfoDownloadState() {
        let downloaded = displayedPeerInfo == nil
        
        for view in [pinButton, ageGenderLabel, traitsButton, pictureDownloadIndicator] {
            view.hidden = downloaded
        }
//        stateLabel.hidden = displayedPeerInfo == nil
        downloadIndicator.hidden = !downloaded
    }
    
    private func displayImageState() {
        guard let peerInfo = displayedPeerInfo else { return }
        
        pictureDownloadIndicator.hidden = !RemotePeerManager.sharedManager.isPictureLoading(peerInfo.peerID)
        portraitImageView.alpha = peerInfo.hasPicture ? 1.0 : 0.5
        portraitImageView.image = peerInfo.picture ?? UIImage(named: "PersonPlaceholder")
    }
    
    private func enablePinButton() {
        pinButton.enabled = displayedPeerID! != UserPeerInfo.instance.peer.peerID && RemotePeerManager.sharedManager.availablePeers.contains(displayedPeerID!)
    }
    
    private func setupTitle() {
        if displayedPeerID == UserPeerInfo.instance.peer.peerID || RemotePeerManager.sharedManager.availablePeers.contains(displayedPeerID!) {
            navigationItem.titleView = nil
        } else {
            let titleLable = UILabel(frame: CGRect(x:0, y:0, width: 200, height: 45))
            titleLable.text = displayedPeerID!.displayName
            titleLable.textColor = UIColor(white: 0.5, alpha: 1.0)
            titleLable.textAlignment = .Center
            titleLable.lineBreakMode = .ByTruncatingTail
            navigationItem.titleView = titleLable
        }
    }
}