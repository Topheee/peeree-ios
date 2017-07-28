//
//  PersonDetailViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class PersonDetailViewController: UIViewController, ProgressDelegate {
	@IBOutlet private weak var portraitImageView: UIImageView!
	@IBOutlet private weak var ageGenderLabel: UILabel!
    @IBOutlet private weak var pinButton: UIButton!
    @IBOutlet private weak var traitsButton: UIButton!
    @IBOutlet private weak var gradientView: UIImageView!
    @IBOutlet private weak var pinIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var findButtonItem: UIBarButtonItem!
    
    private static let unwindSegueID = "unwindToBrowseViewController"
    static let beaconSegueID = "beaconSegue"
    
    private struct PeerState {
        let peer: PeerInfo
        
        enum ConnectionState {
            case connected, disconnected
        }
        
        enum PinState {
            case pinned, pinning, notPinned
        }
        
        enum DownloadState {
            case notDownloaded, downloading, downloaded
        }
        
        var isLocalPeer: Bool { return peer.peerID == UserPeerInfo.instance.peer.peerID }
        var isOnline: Bool { return PeeringController.shared.peering }
        var isAvailable: Bool { return PeeringController.shared.remote.availablePeers.contains(peer.peerID) }
        
        var pictureDownloadState: DownloadState {
            if peer.picture == nil {
                return PeeringController.shared.remote.isPictureLoading(of: peer.peerID) != nil ? .downloading : .notDownloaded
            } else {
                return .downloaded
            }
        }
        
        var pictureDownloadProgress: Double {
            return PeeringController.shared.remote.isPictureLoading(of: peer.peerID)?.fractionCompleted ?? 0.0
        }
        
        var pinState: PinState {
            if peer.pinned {
                return .pinned
            } else {
                return AccountController.shared.isPinning(peer.peerID) ? .pinning : .notPinned
            }
        }
        
        var pinMatch: Bool {
            return peer.pinMatched
        }
    }
    
    private var notificationObservers: [NSObjectProtocol] = []
    private var circleLayer: CAShapeLayer!
    
    var displayedPeerInfo: PeerInfo?
    
    var pictureProgressManager: ProgressManager?
    
    @IBAction func unwindToBrowseViewController(_ segue: UIStoryboardSegue) {}
    
	@IBAction func pinPeer(_ sender: UIButton) {
        guard let peer = displayedPeerInfo else { return }
        guard !peer.pinned else {
            AccountController.shared.updatePinStatus(of: peer.peerID)
            return
        }
        
        AppDelegate.requestPin(of: peer)
        updateState()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let charTraitVC = segue.destination as? CharacterTraitViewController {
            charTraitVC.characterTraits = displayedPeerInfo?.characterTraits
            charTraitVC.userTraits = false
        } else if let beaconVC = segue.destination as? BeaconViewController {
            beaconVC.searchedPeer = displayedPeerInfo
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        pinButton.setImage(#imageLiteral(resourceName: "PinTemplatePressed"), for: [.disabled, .selected])
    }
    
	override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        updateState()
        
        let simpleStateUpdate = { (notification: Notification) in
            guard let peerID = notification.userInfo?[PeeringController.NetworkNotificationKey.peerID.rawValue] as? PeerID else { return }
            guard self.displayedPeerInfo?.peerID == peerID else { return }
            self.updateState()
        }
        
        let simpleHandledNotifications: [PeeringController.Notifications] = [.peerAppeared, .peerDisappeared]
        for networkNotification in simpleHandledNotifications {
            notificationObservers.append(networkNotification.addObserver(usingBlock: simpleStateUpdate))
        }
        
        let simpleHandledNotifications2: [AccountController.Notifications] = [.pinned, .pinningStarted, .pinFailed]
        for networkNotification in simpleHandledNotifications2 {
            notificationObservers.append(networkNotification.addObserver(usingBlock: simpleStateUpdate))
        }
        
        notificationObservers.append(AccountController.Notifications.pinMatch.addObserver(usingBlock: { (notification) in
            simpleStateUpdate(notification)
            self.animateGradient()
        }))
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let peer = displayedPeerInfo else { return }
        
        if let progress = PeeringController.shared.remote.loadPicture(of: peer) {
            pictureProgressManager = ProgressManager(peerID: peer.peerID, progress: progress, delegate: self, queue: DispatchQueue.main)
            
            // localize clockwise progress drawing
            let clockwiseProgress: Bool
            if let langCode = Locale.current.languageCode {
                let direction = Locale.characterDirection(forLanguage: langCode)
                clockwiseProgress = direction == .leftToRight || direction == .topToBottom
            } else {
                clockwiseProgress = true
            }
            let circlePath: UIBezierPath
            let size = portraitImageView.frame.size
            if clockwiseProgress {
                circlePath = UIBezierPath(arcCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0 - 42.0), radius: 42 /* (size.width - 35)/2 */, startAngle: .pi * CGFloat(0.5), endAngle: .pi * CGFloat(2.5), clockwise: clockwiseProgress)
            } else {
                circlePath = UIBezierPath(arcCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0 - 42.0), radius: 42 /* (size.width - 35)/2 */, startAngle: .pi * CGFloat(2.5), endAngle: .pi * CGFloat(0.5), clockwise: clockwiseProgress)
            }
            
            // Setup the CAShapeLayer with the path, colors, and line width
            circleLayer = CAShapeLayer()
            circleLayer.frame = CGRect(origin: CGPoint.zero, size: size)
            circleLayer.path = circlePath.cgPath
            circleLayer.fillColor = UIColor.clear.cgColor
            circleLayer.strokeColor = AppDelegate.shared.theme.globalTintColor.cgColor
            circleLayer.lineWidth = 5.0
            circleLayer.lineCap = kCALineCapRound
            circleLayer.shadowColor = UIColor.gray.cgColor
            circleLayer.strokeEnd = CGFloat(progress.fractionCompleted)
            
            // Add the circleLayer to the view's layer's sublayers
            portraitImageView.layer.addSublayer(circleLayer)
        }
        
        if peer.pinMatched {
            animateGradient()
        }
    }
    
    private func animateGradient() {
        UIView.animate(withDuration: 1.5, delay: 0.0, usingSpringWithDamping: 2.0, initialSpringVelocity: 1.2, options: [.repeat, .autoreverse], animations: {
            self.gradientView.alpha = 0.5
        }, completion: nil)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        _ = CircleMaskView(maskedView: portraitImageView)
//        portraitImageView.layer.cornerRadius = portraitImageView.frame.width / 2
//        portraitImageView.layer.masksToBounds = true
        
        updateState()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        gradientView.layer.removeAllAnimations()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pictureProgressManager = nil
        circleLayer = nil
        portraitImageView.image = nil
    }
    
    // MARK: ProgressDelegate
    
    func progress(didPause progress: Progress, peerID: PeerID) {
        // ignored
    }
    
    func progress(didCancel progress: Progress, peerID: PeerID) {
        if progress === pictureProgressManager?.progress {
            removePictureLoadLayer()
            //            UIView.animate(withDuration: 1.0, delay: 0.0, options: [.autoreverse], animations: {
            //                self.portraitImageView.backgroundColor = UIColor.red
            //            }) { (completed) in
            //                    self.portraitImageView.backgroundColor = nil
            //            }
            // as above is not working...
            UIView.animate(withDuration: 1.0, delay: 0.0, options: [], animations: {
                self.portraitImageView.backgroundColor = UIColor.red
            }) { (completed) in
                UIView.animate(withDuration: 1.0, delay: 0.0, options: [], animations: {
                    self.portraitImageView.backgroundColor = nil
                }, completion: nil)
            }
            pictureProgressManager = nil
        }
    }
    
    func progress(didResume progress: Progress, peerID: PeerID) {
        // ignored
    }
    
    func progress(didUpdate progress: Progress, peerID: PeerID) {
        if progress === pictureProgressManager?.progress {
            if progress.completedUnitCount == progress.totalUnitCount {
                pictureProgressManager = nil
                // as we have value semantics, our cached peer info does not change, so we have to get the updated one
                displayedPeerInfo = PeeringController.shared.remote.getPeerInfo(of: peerID)
                removePictureLoadLayer()
                updateState()
            } else {
                circleLayer?.strokeEnd = CGFloat(progress.fractionCompleted)
            }
        }
    }

    // MARK: Private methods
    
    private func updateState() {
        guard let peer = displayedPeerInfo else { return }
        let state = PeerState(peer: peer)
        
        pinButton.isHidden = state.pinState == .pinning
        pinButton.isEnabled = state.isAvailable && !state.isLocalPeer
        pinButton.isSelected = state.pinState == .pinned
//        traitsButton.isHidden = state.peerInfoDownloadState != .downloaded
        gradientView.isHidden = !state.pinMatch || state.isLocalPeer
        pinIndicator.isHidden = state.pinState != .pinning
        findButtonItem.isEnabled = state.pinMatch
        
        title = peer.nickname
        if state.isLocalPeer || state.isAvailable {
            navigationItem.titleView = nil
            navigationItem.title = peer.nickname
        } else {
            let titleLable = UILabel(frame: CGRect(x:0, y:0, width: 200, height: 45))
            titleLable.text = peer.nickname
            titleLable.textColor = UIColor.lightGray
            titleLable.textAlignment = .center
            titleLable.lineBreakMode = .byTruncatingTail
            navigationItem.titleView = titleLable
        }
        
        ageGenderLabel.text = peer.summary
        portraitImageView.image = peer.picture ?? (peer.hasPicture ? #imageLiteral(resourceName: "PortraitPlaceholder") : #imageLiteral(resourceName: "PortraitUnavailable"))
    }
    
    private func removePictureLoadLayer() {
//        portraitImageView.layer.sublayers?.last?.removeFromSuperlayer()
        circleLayer?.removeFromSuperlayer()
        circleLayer = nil
    }
}
