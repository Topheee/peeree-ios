//
//  PersonDetailViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import MultipeerConnectivity

final class PersonDetailViewController: UIViewController, PotraitLoadingDelegate {
	@IBOutlet private weak var portraitImageView: UIImageView!
	@IBOutlet private weak var ageGenderLabel: UILabel!
	@IBOutlet private weak var stateLabel: UILabel!
    @IBOutlet private weak var downloadIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var pinButton: UIButton!
    @IBOutlet private weak var traitsButton: UIButton!
    @IBOutlet private weak var gradientView: UIImageView!
    @IBOutlet private weak var pinIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var findButtonItem: UIBarButtonItem!
    
    private static let unwindSegueID = "unwindToBrowseViewController"
    static let beaconSegueID = "beaconSegue"
    
    private var notificationObservers: [AnyObject] = []
    private var circleLayer: CAShapeLayer!
    
    private var displayedPeerInfo: PeerInfo? {
        if displayedPeerID! != UserPeerInfo.instance.peer.peerID {
            return RemotePeerManager.sharedManager.getPeerInfo(forPeer: displayedPeerID!, download: true)
        } else {
            return UserPeerInfo.instance.peer
        }
    }
    
    var displayedPeerID: MCPeerID?
    
    struct PeerState {
        
        let peerID: MCPeerID
        
        enum ConnectionState {
            case Connected, Disconnected
        }
        
        enum PinState {
            case Pinned, Pinning, NotPinned
        }
        
        enum DownloadState {
            case NotDownloaded, Downloading, Downloaded
        }
        
        var isLocalPeer: Bool { return peerID == UserPeerInfo.instance.peer.peerID }
        
        var isOnline: Bool { return RemotePeerManager.sharedManager.peering }
        
        var isAvailable: Bool { return RemotePeerManager.sharedManager.availablePeers.contains(peerID) }
        
        var peerInfoDownloadState: DownloadState {
            guard !isLocalPeer && RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID, download: false) == nil else { return .Downloaded }
            return RemotePeerManager.sharedManager.isPeerInfoLoading(ofPeerID: peerID) ? .Downloading : .NotDownloaded
        }
        
        var pictureDownloadState: DownloadState {
            guard let peer = RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID, download: false) else { return .NotDownloaded }
            if peer.picture == nil {
                return peer.isPictureLoading ? .Downloading : .NotDownloaded
            } else {
                return .Downloaded
            }
        }
        
        var pictureDownloadProgress: Double {
            return RemotePeerManager.sharedManager.getPictureLoadFraction(ofPeer: peerID)
        }
        
        var pinState: PinState {
            guard let peer = RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID, download: false) else { return .NotPinned }
            if peer.pinned {
                return .Pinned
            } else {
                return RemotePeerManager.sharedManager.isPinning(peerID) ? .Pinning : .NotPinned
            }
        }
        
        var pinMatch: Bool {
            guard let peer = RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID, download: false) else { return false }
            return peer.pinMatched
        }
    }
    
    private func removePictureLoadLayer() {
        portraitImageView.layer.sublayers?.last?.removeFromSuperlayer()
        circleLayer = nil
    }
    
    private func updateState() {
        guard let peerID = displayedPeerID else { return }
        let state = PeerState(peerID: peerID)
        
        portraitImageView.hidden = state.peerInfoDownloadState != .Downloaded
        ageGenderLabel.hidden = state.peerInfoDownloadState != .Downloaded
//        stateLabel.hidden = state.peerInfoDownloadState != .Downloaded
        downloadIndicator.hidden = state.peerInfoDownloadState != .Downloading
        pinButton.hidden = state.peerInfoDownloadState != .Downloaded
        pinButton.enabled = state.isAvailable && !state.isLocalPeer
        pinButton.selected = state.pinState == .Pinned
        traitsButton.hidden = state.peerInfoDownloadState != .Downloaded
        gradientView.hidden = !state.pinMatch || state.isLocalPeer
        pinIndicator.hidden = state.pinState != .Pinning
        findButtonItem.enabled = state.pinMatch
        
        if state.pictureDownloadState == .Downloading {
            
            if circleLayer == nil {
                // Use UIBezierPath as an easy way to create the CGPath for the layer.
                // The path should be the entire circle.
                let size = portraitImageView.frame.size
                let circlePath = UIBezierPath(arcCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0), radius: (size.width - 30)/2, startAngle: CGFloat(M_PI * 0.5), endAngle: CGFloat(M_PI * 2.5), clockwise: true)
                
                // Setup the CAShapeLayer with the path, colors, and line width
                circleLayer = CAShapeLayer()
                circleLayer.path = circlePath.CGPath
                circleLayer.fillColor = UIColor.clearColor().CGColor
                circleLayer.strokeColor = theme.globalTintColor.CGColor
                circleLayer.lineWidth = 15.0;
                
                // Add the circleLayer to the view's layer's sublayers
                portraitImageView.layer.addSublayer(circleLayer)
            }
            
            circleLayer?.strokeEnd = CGFloat(state.pictureDownloadProgress)
        }
        
        if state.isLocalPeer || state.isAvailable {
            navigationItem.titleView = nil
        } else {
            let titleLable = UILabel(frame: CGRect(x:0, y:0, width: 200, height: 45))
            titleLable.text = peerID.displayName
            titleLable.textColor = UIColor(white: 0.5, alpha: 1.0)
            titleLable.textAlignment = .Center
            titleLable.lineBreakMode = .ByTruncatingTail
            navigationItem.titleView = titleLable
        }
        
        guard let peerInfo = displayedPeerInfo else { return }
        
        portraitImageView.image = peerInfo.picture ?? UIImage(named: peerInfo.hasPicture ? "PortraitPlaceholder" : "PortraitUnavailable")
    }
    
    @IBAction func unwindToBrowseViewController(segue: UIStoryboardSegue) {
        
    }
    
	@IBAction func pinPeer(sender: UIButton) {
        guard let peer = displayedPeerInfo else { return }
        guard !peer.pinned else { return }
        
        RemotePeerManager.sharedManager.pinPeer(peer.peerID)
        updateState()
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if let charTraitVC = segue.destinationViewController as? CharacterTraitViewController {
            charTraitVC.characterTraits = displayedPeerInfo?.characterTraits
            charTraitVC.userTraits = false
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        pinButton.setImage(UIImage(named: "PinTemplatePressed"), forState: [.Disabled, .Selected])
        
        UIView.animateWithDuration(1.5, delay: 0.0, usingSpringWithDamping: 2.0, initialSpringVelocity: 1.0, options: [.Repeat, .Autoreverse], animations: {
            self.gradientView.alpha = 0.0
            }, completion: nil)
    }
    
	override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        guard displayedPeerID != nil else { assertionFailure(); return }
        
        displayPeerInfo()
        navigationItem.title = displayedPeerID!.displayName
        
        if let peerInfo = displayedPeerInfo {
            RemotePeerManager.sharedManager.loadPicture(forPeer: peerInfo, delegate: self)
        }
        
        updateState()
        
        let simpleStateUpdate = { (notification: NSNotification) in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }
            guard self.displayedPeerID == peerID else { return }
            self.updateState()
        }
        
        let simpleHandledNotifications: [RemotePeerManager.NetworkNotification] = [.RemotePeerAppeared, .RemotePeerDisappeared, .PictureLoaded, .PinMatch, .Pinned, .PinFailed, .PictureLoadFailed]
        for networkNotification in simpleHandledNotifications {
            notificationObservers.append(networkNotification.addObserver(usingBlock: simpleStateUpdate))
        }
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.PeerInfoLoaded.addObserver { (notification) in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }
            guard self.displayedPeerID == peerID else { return }
            guard let peerInfo = self.displayedPeerInfo else { assertionFailure(); return }
            
            RemotePeerManager.sharedManager.loadPicture(forPeer: peerInfo, delegate: self)
            self.displayPeerInfo()
            self.updateState()
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.PeerInfoLoadFailed.addObserver { (notification) in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }
            guard self.displayedPeerID == peerID else { return }
            
            self.performSegueWithIdentifier(PersonDetailViewController.unwindSegueID, sender: self)
        })
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        portraitImageView.maskView = CircleMaskView(frame: portraitImageView.bounds)
        
        // as our layout changed the frame of the portrait view, we have to recalculate the circleLayer
        removePictureLoadLayer()
        updateState()
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        for observer in notificationObservers {
            NSNotificationCenter.defaultCenter().removeObserver(observer)
        }
    }
    
    // MARK: PotraitLoadingDelegate
    
    func portraitLoadFailed(withError error: NSError) {
        // TODO handle error, e.g. same cancel animation as to be inserted in portraitLoadCancelled()
        dispatch_async(dispatch_get_main_queue()) {
            self.removePictureLoadLayer()
            UIView.animateWithDuration(1.0, delay: 0.0, options: [.Autoreverse], animations: {
                self.portraitImageView.backgroundColor = UIColor.redColor()
            }, completion: nil)
        }
    }
    
    func portraitLoadFinished() {
        dispatch_async(dispatch_get_main_queue()) {
            self.removePictureLoadLayer()
            self.updateState()
        }
    }
    
    func portraitLoadCancelled() {
        dispatch_async(dispatch_get_main_queue()) {
            self.removePictureLoadLayer()
            UIView.animateWithDuration(1.0, delay: 0.0, options: [.Autoreverse], animations: {
                self.portraitImageView.backgroundColor = UIColor.redColor()
            }, completion: nil)
        }
    }
    
    func portraitLoadChanged(fractionCompleted: Double) {
        dispatch_async(dispatch_get_main_queue()) {
            self.circleLayer.strokeEnd = CGFloat(fractionCompleted)
        }
    }
    
    // MARK: Private methods
    
    private func displayPeerInfo() {
        guard let peerInfo = displayedPeerInfo else { return }
        
        ageGenderLabel.text = peerInfo.summary
        stateLabel.text = peerInfo.relationshipStatus.localizedRawValue
    }
}