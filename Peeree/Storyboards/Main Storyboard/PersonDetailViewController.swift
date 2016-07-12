//
//  PersonDetailViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import MultipeerConnectivity

final class PersonDetailViewController: UIViewController, RemotePeerManagerDelegate {
	@IBOutlet private var portraitImageView: UIImageView!
	@IBOutlet private var ageGenderLabel: UILabel!
	@IBOutlet private var stateLabel: UILabel!
    @IBOutlet private weak var downloadIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var pinButton: UIButton!
    @IBOutlet private weak var pictureDownloadIndicator: UIActivityIndicatorView!
    
    private var superConnectionDelegate: RemotePeerManagerDelegate?
    
    var displayedPeer: MCPeerID?
    
    var displayedPeerInfo: PeerInfo? {
        if UserPeerInfo.instance.peer.peerID == displayedPeer {
            return UserPeerInfo.instance.peer
        } else if let peerID = displayedPeer {
            return RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID, download: true)
        }
        return nil
    }
	
	@IBAction func pinPeer(sender: UIButton) {
		// TODO pin this peer
	}
    
	override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        guard displayedPeer != nil else { assertionFailure(); return }
        
        superConnectionDelegate = RemotePeerManager.sharedManager.delegate
//        RemotePeerManager.sharedManager.delegate = self
        
        navigationItem.title = displayedPeer?.displayName
        
        NSNotificationCenter.defaultCenter().addObserverForName(RemotePeerManager.RemotePeerAppearedNotification, object: nil, queue: NSOperationQueue.mainQueue()) { (notification) in
            if let peerID = notification.userInfo?[RemotePeerManager.PeerIDKey] as? MCPeerID {
                self.remotePeerAppeared(peerID)
            }
        }
        
        NSNotificationCenter.defaultCenter().addObserverForName(RemotePeerManager.RemotePeerDisappearedNotification, object: nil, queue: NSOperationQueue.mainQueue()) { (notification) in
            if let peerID = notification.userInfo?[RemotePeerManager.PeerIDKey] as? MCPeerID {
                self.remotePeerDisappeared(peerID)
            }
        }
        
        NSNotificationCenter.defaultCenter().addObserverForName(RemotePeerManager.ConnectionChangedStateNotification, object: nil, queue: NSOperationQueue.mainQueue()) { (notification) in
            self.connectionChangedState(RemotePeerManager.sharedManager.peering)
        }
        
        NSNotificationCenter.defaultCenter().addObserverForName(RemotePeerManager.PeerInfoLoadedNotification, object: nil, queue: NSOperationQueue.mainQueue()) { (notification) in
            if let peerID = notification.userInfo?[RemotePeerManager.PeerIDKey] as? MCPeerID {
                self.peerInfoLoaded(RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID)!)
            }
        }
        
        guard displayedPeerInfo != nil else { return }
        
        displayPeerInfo(displayedPeerInfo!)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        portraitImageView.maskView = CircleMaskView(forView: portraitImageView)
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        displayPeerInfoDownloadState(displayedPeerInfo != nil)
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        // unfortunately the test whether someone else changed the RemotePeerManager's delegate does not work because somehow you cannot compare protocol variables
//        if let actualDelegate = RemotePeerManager.sharedManager.delegate {
//            if actualDelegate == self as RemotePeerManagerDelegate {
//                RemotePeerManager.sharedManager.delegate = superConnectionDelegate
//            }
//        }
    }
    
    // MARK: RemotePeerManager Delegate
    
    func remotePeerAppeared(peer: MCPeerID) {
        if displayedPeer != nil && displayedPeer! == peer {
            displayPeerInfoDownloadState(true)
        }
        superConnectionDelegate?.remotePeerAppeared(peer)
    }
    
    func remotePeerDisappeared(peer: MCPeerID) {
        // disable pin button to show connection loss
        // Peeree 2.0: enable lazy pinning, see classification sheet
        if displayedPeer != nil && displayedPeer! == peer {
            displayPeerInfoDownloadState(false)
        }
        superConnectionDelegate?.remotePeerDisappeared(peer)
    }
    
    func connectionChangedState(nowOnline: Bool) {
        // don't handle this, should probably never happen anyway
        superConnectionDelegate?.connectionChangedState(nowOnline)
    }
    
    func peerInfoLoaded(peerInfo: PeerInfo) {
        if displayedPeer != nil && displayedPeer! == peerInfo.peerID {
            displayPeerInfo(peerInfo)
            superConnectionDelegate?.peerInfoLoaded(peerInfo)
        }
    }
    
    // MARK: Private methods
    
    private func displayPeerInfo(peerInfo: PeerInfo) {
        //TODO localization
        ageGenderLabel.text = "\(peerInfo.age) years old, \(peerInfo.gender.localizedRawValue())"
        stateLabel.text = UserPeerInfo.instance.relationshipStatus.localizedRawValue()
        displayNewImageState(peerInfo)
        RemotePeerManager.sharedManager.loadPicture(peerInfo) { (peerInfo) in
            self.displayNewImageState(peerInfo)
        }
        pinButton.enabled = peerInfo != UserPeerInfo.instance.peer
    }
    
    private func displayPeerInfoDownloadState(downloaded: Bool) {
        pinButton.hidden = !downloaded
        downloadIndicator.hidden = downloaded
    }
    
    private func displayNewImageState(peerInfo: PeerInfo) {
        portraitImageView.image = peerInfo.picture ?? UIImage(named: "PersonPlaceholder")
        pictureDownloadIndicator.hidden = RemotePeerManager.sharedManager.isPictureLoading(peerInfo.peerID)
    }
}