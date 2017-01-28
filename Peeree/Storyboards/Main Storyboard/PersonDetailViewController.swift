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
	@IBOutlet private weak var stateLabel: UILabel!
    @IBOutlet private weak var downloadIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var pinButton: UIButton!
    @IBOutlet private weak var traitsButton: UIButton!
    @IBOutlet private weak var gradientView: UIImageView!
    @IBOutlet private weak var pinIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var findButtonItem: UIBarButtonItem!
    
    private static let unwindSegueID = "unwindToBrowseViewController"
    static let beaconSegueID = "beaconSegue"
    
    private struct PeerState {
        let peerID: PeerID
//        lazy var _peerInfo = PeeringController.shared.remote.getPeerInfo(of: self.peerID, download: false)
        
        enum ConnectionState {
            case connected, disconnected
        }
        
        enum PinState {
            case pinned, pinning, notPinned
        }
        
        enum DownloadState {
            case notDownloaded, downloading, downloaded
        }
        
        var isLocalPeer: Bool { return peerID == UserPeerInfo.instance.peer.peerID }
        var isOnline: Bool { return PeeringController.shared.peering }
        var isAvailable: Bool { return PeeringController.shared.availablePeers.contains(peerID) }
        
        var peerInfoDownloadState: DownloadState {
            guard !isLocalPeer && PeeringController.shared.remote.getPeerInfo(of: peerID) == nil else { return .downloaded }
            return PeeringController.shared.remote.isPeerInfoLoading(of: peerID) != nil ? .downloading : .notDownloaded
        }
        
        var pictureDownloadState: DownloadState {
            guard let peer = PeeringController.shared.remote.getPeerInfo(of: peerID) else { return .notDownloaded }
            if peer.picture == nil {
                return PeeringController.shared.remote.isPictureLoading(of: peerID) != nil ? .downloading : .notDownloaded
            } else {
                return .downloaded
            }
        }
        
        var pictureDownloadProgress: Double {
            return PeeringController.shared.remote.isPictureLoading(of: peerID)?.fractionCompleted ?? 0.0
        }
        
        var pinState: PinState {
            guard let peer = PeeringController.shared.remote.getPeerInfo(of: peerID) else { return .notPinned }
            if peer.pinned {
                return .pinned
            } else {
                return PeeringController.shared.local.isPinning(peerID) ? .pinning : .notPinned
            }
        }
        
        var pinMatch: Bool {
            guard let peer = PeeringController.shared.remote.getPeerInfo(of: peerID) else { return false }
            return peer.pinMatched
        }
    }
    
    private var notificationObservers: [NSObjectProtocol] = []
    private var circleLayer: CAShapeLayer!
    
    private var displayedPeerInfo: PeerInfo? {
        if displayedPeerID! != UserPeerInfo.instance.peer.peerID {
            return PeeringController.shared.remote.getPeerInfo(of: displayedPeerID!)
        } else {
            return UserPeerInfo.instance.peer
        }
    }
    
    var displayedPeerID: PeerID?
    var pictureProgressManager: ProgressManager?
    var peerInfoProgressManager: ProgressManager?
    
    @IBAction func unwindToBrowseViewController(_ segue: UIStoryboardSegue) {}
    
	@IBAction func pinPeer(_ sender: UIButton) {
        guard let peer = displayedPeerInfo else { return }
        guard !peer.pinned else { return }
        
        PeeringController.shared.pin(peer.peerID)
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
        pinButton.setImage(UIImage(named: "PinTemplatePressed"), for: [.disabled, .selected])
        
        UIView.animate(withDuration: 1.5, delay: 0.0, usingSpringWithDamping: 2.0, initialSpringVelocity: 1.2, options: [.repeat, .autoreverse], animations: {
            self.gradientView.alpha = 0.5
            }, completion: nil)
    }
    
	override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard displayedPeerID != nil else { assertionFailure(); return }
        
        if let progress = PeeringController.shared.remote.loadPeerInfo(of: displayedPeerID!) {
            peerInfoProgressManager = ProgressManager(peerID: displayedPeerID!, progress: progress, delegate: self, queue: DispatchQueue.main)
        } else if let peerInfo = displayedPeerInfo {
            if let progress = PeeringController.shared.remote.loadPicture(of: peerInfo) {
                pictureProgressManager = ProgressManager(peerID: peerInfo.peerID, progress: progress, delegate: self, queue: DispatchQueue.main)
            }
        }
        
        displayPeerInfo()
        navigationItem.title = displayedPeerID!.displayName
        
        updateState()
        
        let simpleStateUpdate = { (notification: Notification) in
            guard let peerID = notification.userInfo?[PeeringController.NetworkNotificationKey.peerID.rawValue] as? PeerID else { return }
            guard self.displayedPeerID == peerID else { return }
            self.updateState()
        }
        
        let simpleHandledNotifications: [PeeringController.NetworkNotification] = [.peerAppeared, .peerDisappeared, .pinMatch, .pinned, .pinningStarted, .pinFailed]
        for networkNotification in simpleHandledNotifications {
            notificationObservers.append(networkNotification.addObserver(usingBlock: simpleStateUpdate))
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        _ = CircleMaskView(maskedView: portraitImageView)
//        portraitImageView.layer.cornerRadius = portraitImageView.frame.width / 2
//        portraitImageView.layer.masksToBounds = true
        
        // as our layout changed the frame of the portrait view, we have to recalculate the circleLayer
        removePictureLoadLayer()
        updateState()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        portraitImageView.image = nil
        circleLayer = nil
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
        } else if progress === peerInfoProgressManager?.progress {
            performSegue(withIdentifier: PersonDetailViewController.unwindSegueID, sender: self)
        }
    }
    
    func progress(didResume progress: Progress, peerID: PeerID) {
        // ignored
    }
    
    func progress(didUpdate progress: Progress, peerID: PeerID) {
        if progress === pictureProgressManager?.progress {
            if progress.completedUnitCount == progress.totalUnitCount {
                pictureProgressManager = nil
                removePictureLoadLayer()
                updateState()
            } else {
                circleLayer?.strokeEnd = CGFloat(progress.fractionCompleted)
            }
        } else if progress === peerInfoProgressManager?.progress {
            guard let peerInfo = self.displayedPeerInfo else { assertionFailure(); return }
            
            if let progress = PeeringController.shared.remote.loadPicture(of: peerInfo) {
                pictureProgressManager = ProgressManager(peerID: displayedPeerID!, progress: progress, delegate: self, queue: DispatchQueue.main)
            }
            displayPeerInfo()
            updateState()
        }
    }

    // MARK: Private methods

    private func displayPeerInfo() {
        guard let peerInfo = displayedPeerInfo else { return }
        
        stateLabel.text = peerInfo.relationshipStatus.localizedRawValue
    }
    
    private func updateState() {
        guard let peerID = displayedPeerID else { return }
        let state = PeerState(peerID: peerID)
        
        portraitImageView.isHidden = state.peerInfoDownloadState != .downloaded
        ageGenderLabel.isHidden = state.peerInfoDownloadState != .downloaded
        //        stateLabel.hidden = state.peerInfoDownloadState != .Downloaded
        downloadIndicator.isHidden = state.peerInfoDownloadState != .downloading
        pinButton.isHidden = state.peerInfoDownloadState != .downloaded
        pinButton.isEnabled = state.isAvailable && !state.isLocalPeer
        pinButton.isSelected = state.pinState == .pinned
        traitsButton.isHidden = state.peerInfoDownloadState != .downloaded
        gradientView.isHidden = !state.pinMatch || state.isLocalPeer
        pinIndicator.isHidden = state.pinState != .pinning
        findButtonItem.isEnabled = state.pinMatch
        
        if state.pictureDownloadState == .downloading {
            
            if circleLayer == nil {
                // Use UIBezierPath as an easy way to create the CGPath for the layer.
                // The path should be the entire circle.
                let size = portraitImageView.frame.size
                let circlePath = UIBezierPath(arcCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0), radius: (size.width - 30)/2, startAngle: CGFloat(M_PI * 0.5), endAngle: CGFloat(M_PI * 2.5), clockwise: true)
                
                // Setup the CAShapeLayer with the path, colors, and line width
                circleLayer = CAShapeLayer()
                circleLayer.path = circlePath.cgPath
                circleLayer.fillColor = UIColor.clear.cgColor
                circleLayer.strokeColor = theme.globalTintColor.cgColor
                circleLayer.lineWidth = 10.0;
                
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
            titleLable.textAlignment = .center
            titleLable.lineBreakMode = .byTruncatingTail
            navigationItem.titleView = titleLable
        }
        
        guard let peerInfo = displayedPeerInfo else { return }
        
        ageGenderLabel.text = peerInfo.summary
        portraitImageView.image = peerInfo.picture ?? UIImage(named: peerInfo.hasPicture ? "PortraitPlaceholder" : "PortraitUnavailable")
    }
    
    private func removePictureLoadLayer() {
        portraitImageView.layer.sublayers?.last?.removeFromSuperlayer()
        circleLayer = nil
    }
}
