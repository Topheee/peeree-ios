//
//  RemotePeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.10.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/// The RemotePeerManager singleton serves as an globally access point for information about all remote peers, whether they are currently in network range or were pinned in the past.
final class RemotePeerManager: NSObject, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
	static private let DiscoveryServiceID = "peeree-discover"
	static private let InvitationTimeout: NSTimeInterval = 5.0
    
    static private let PinnedPeersKey = "PinnedPeers"
    static private let PinnedByPeersKey = "PinnedByPeers"
    
    /// Identifies a MCSession as a session which transfers LocalPeerInfo objects.
    static private let PeerInfoSessionKey = "PeerInfoSession"
    /// Session key for transmitting portrait images.
    static private let PictureSessionKey = "PictureSession"
    /// Session key for populating pin status.
    static private let PinSessionKey = "PinSession"
    
    static let RemotePeerAppearedNotification = "RemotePeerAppeared"
    static let RemotePeerDisappearedNotification = "RemotePeerDisappeared"
    static let ConnectionChangedStateNotification = "ConnectionChangedState"
    static let PeerInfoLoadedNotification = "PeerInfoLoaded"
    static let PictureLoadedNotification = "PictureLoaded"
    static let PinMatchNotification = "Pinned"
    
    static let PeerIDKey = "PeerID"
    
    static let sharedManager = RemotePeerManager()
	
	/*
	 *	Since bluetooth connections are not very reliable, all peers and their images are cached for a reasonable amount of time (at least 30 Minutes).
	 */
    private var cachedPeers: [MCPeerID : LocalPeerInfo] = [:]
    private var loadingPictures: Set<MCPeerID> = Set()
    
	/*
	 *	All the Bluetooth stuff.
	 *	Should be private, but then, we cannot mock them.
	 */
	/* private */ var btAdvertiser: MCNearbyServiceAdvertiser?
	/* private */ var btBrowser: MCNearbyServiceBrowserMock?
    
	/*
	 *	All remote peers the app is currently connected to. This property is immediatly updated when a new connection is set up or an existing is cut off.
	 */
	private var _availablePeers = Set<MCPeerID>() // TODO convert into NSOrderedSet to not always confuse the order of the browse view
    
    /// stores pinned peers and whether the pin was acknowledged by them
    private var pinnedPeers: [MCPeerID : Bool]
    // maybe encrypt these on disk so no one can read out their display names
    private var pinnedByPeers: Set<MCPeerID>
    
    var availablePeers: Set<MCPeerID> {
        return _availablePeers
    }
    
    var peering: Bool {
        get {
            return btAdvertiser != nil && btBrowser != nil
        }
        set {
            guard newValue != peering else { return }
            if newValue {
                let peerID = UserPeerInfo.instance.peer.peerID
                
                btAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: RemotePeerManager.DiscoveryServiceID)
                btAdvertiser!.delegate = self
                btBrowser = MCNearbyServiceBrowserMock(peer: peerID, serviceType: RemotePeerManager.DiscoveryServiceID)
                btBrowser!.delegate = self
                
                self.connectionChangedState()
                
                btAdvertiser?.startAdvertisingPeer()
                btBrowser?.startBrowsingForPeers()
            } else {
                btAdvertiser?.stopAdvertisingPeer()
                btBrowser?.stopBrowsingForPeers()
                btAdvertiser = nil
                btBrowser = nil
                _availablePeers.removeAll()
                loadingPictures.removeAll()
                self.connectionChangedState()
                // TODO maybe cancel and close all sessions in the MCSessionDelegateAdapter class
            }
        }
    }
    
    func isPeerPinned(peerID: MCPeerID) -> Bool {
        return pinnedPeers.indexForKey(peerID) != nil
    }
    
    func hasPinMatch(peerID: MCPeerID) -> Bool {
        return isPeerPinned(peerID) && pinnedByPeers.contains(peerID)
    }
    
    func loadPicture(forPeer: PeerInfo) {
        if forPeer.hasPicture && forPeer.picture == nil && !isPictureLoading(forPeer.peerID) && peering {
            loadingPictures.insert(forPeer.peerID)
            let handler = PictureDownloadSessionHandler(peerID: forPeer.peerID)
            assert(handler != nil)
        }
    }
    
    func isPictureLoading(ofPeer: MCPeerID) -> Bool {
        return loadingPictures.contains(ofPeer)
    }
    
    func getPeerInfo(forPeer peerID: MCPeerID, download: Bool = false) -> PeerInfo? {
        if let ret = cachedPeers[peerID]?.peer {
            return ret
        } else if download && peering {
            let handler = PeerInfoDownloadSessionHandler(forPeer: peerID)
            assert(handler != nil)
        }
        return nil
    }
    
    func pinPeer(peerID: MCPeerID, successfullCallback: () -> Void) {
        guard pinnedPeers.indexForKey(peerID) == nil || pinnedPeers[peerID] == false else { return }
        
        WalletController.requestPin { 
            if self.pinnedPeers.indexForKey(peerID) == nil && self.pinnedByPeers.contains(peerID) {
                self.pinMatchOccured(peerID)
            }
            
            self.pinnedPeers[peerID] = false
            archiveObjectInUserDefs(self.pinnedPeers as NSDictionary, forKey: RemotePeerManager.PinnedPeersKey)
            let handler = PinSessionHandler(peerID: peerID)
            assert(handler != nil)
            successfullCallback()
        }
    }
	
	// MARK: - MCNearbyServiceAdvertiserDelegate
	
	@objc func advertiser(advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer: NSError) {
        // here one could log the error and send it via internet, but in a very very future
		peering = false
	}
	
	@objc func advertiser(advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: NSData?, invitationHandler: (Bool, MCSession) -> Void) {
        guard let sessionKeyData = context else { return }
        guard let sessionKey = String(data: sessionKeyData, encoding: NSASCIIStringEncoding) else { return }
        
        switch sessionKey {
        case RemotePeerManager.PeerInfoSessionKey:
            let _ = PeerInfoUploadSessionManager(fromPeer: peerID, invitationHandler: invitationHandler)
        case RemotePeerManager.PictureSessionKey:
            let _ = PictureUploadSessionManager(fromPeer: peerID, invitationHandler: invitationHandler)
        case RemotePeerManager.PinSessionKey:
            let _ = PinnedSessionManager(fromPeer: peerID, invitationHandler: invitationHandler)
        default:
            invitationHandler(false, MCSession())
        }
	}
	
	// MARK: MCNearbyServiceBrowserDelegate
	
	@objc func browser(browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: NSError) {
		// here one could log the error and send it via internet, but in a very very future
        peering = false
	}
	
    @objc func browser(browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard !_availablePeers.contains(peerID) else { return }
        
        _availablePeers.insert(peerID)
        self.remotePeerAppeared(peerID)
        
        if pinnedPeers.keys.contains(peerID) && pinnedPeers[peerID] == false {
            let _ = PinSessionHandler(peerID: peerID)
        }
	}
	
	@objc func browser(browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		_availablePeers.remove(peerID)
		self.remotePeerDisappeared(peerID)
    }
    
    // MARK: Private Methods
    
    private override init() {
        let nsPinned: NSDictionary? = unarchiveObjectFromUserDefs(RemotePeerManager.PinnedPeersKey)
        pinnedPeers = nsPinned as? [MCPeerID : Bool] ?? [:]
        let nsPinnedBy: NSSet? = unarchiveObjectFromUserDefs(RemotePeerManager.PinnedByPeersKey)
        pinnedByPeers = nsPinnedBy as? Set<MCPeerID> ?? Set()
    }
    
    private func remotePeerAppeared(peerID: MCPeerID) {
        NSNotificationCenter.defaultCenter().postNotificationName(RemotePeerManager.RemotePeerAppearedNotification, object: self, userInfo: [RemotePeerManager.PeerIDKey : peerID])
    }
    
    private func remotePeerDisappeared(peerID: MCPeerID) {
        NSNotificationCenter.defaultCenter().postNotificationName(RemotePeerManager.RemotePeerDisappearedNotification, object: self, userInfo: [RemotePeerManager.PeerIDKey : peerID])
    }
    
    private func connectionChangedState() {
        NSNotificationCenter.defaultCenter().postNotificationName(RemotePeerManager.ConnectionChangedStateNotification, object: self, userInfo: nil)
    }
    
    private func pinMatchOccured(peerID: MCPeerID) {
        NSNotificationCenter.defaultCenter().postNotificationName(RemotePeerManager.PinMatchNotification, object: RemotePeerManager.sharedManager, userInfo: [RemotePeerManager.PeerIDKey : peerID])
    }
    
    // MARK: - Private classes
    
    private class MCSessionDelegateAdapter: NSObject, MCSessionDelegate {
        
        /// Only used to keep a reference to the session handlers so the RemotePeerManager does not have to.
        private var activeSessions: Set<MCSessionDelegateAdapter> = Set()
        
        var session = MCSession(peer: UserPeerInfo.instance.peer.peerID, securityIdentity: nil, encryptionPreference: .Required)
        
        override init() {
            super.init()
            activeSessions.insert(self)
            session.delegate = self
        }
        
        func sendData(data: NSData, toPeers peerIDs: [MCPeerID]) {
            do {
                try session.sendData(data, toPeers: peerIDs, withMode: .Reliable)
            } catch let error as NSError where error.domain == MCErrorDomain {
                guard let errorCode = MCErrorCode(rawValue: error.code) else {
                    print("Info sending failed due to unkown error: \(error)")
                    session.disconnect()
                    return
                }
                
                switch errorCode {
                case .Unknown, .NotConnected, .TimedOut, .Cancelled, .Unavailable:
                    // cancel gracefully here
                    // error is known, peer is not connected, connection attempt timed out or cancelled by user or multipeer connectivity is currently unavailable.
                    session.disconnect()
                case .InvalidParameter, .Unsupported:
                    // seems that we did something wrong here
                    assertionFailure()
                    session.disconnect()
                }
            } catch let error as NSError {
                print("Info sending failed due to unkown error: \(error)")
                session.disconnect()
            }
        }
        
        // ignored
        @objc func session(session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, withProgress progress: NSProgress) {}
        @objc func session(session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, atURL localURL: NSURL, withError error: NSError?) {}
        @objc func session(session: MCSession, didReceiveStream stream: NSInputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
        @objc func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {}
        
        @objc func session(session: MCSession, didReceiveCertificate certificate: [AnyObject]?, fromPeer peerID: MCPeerID, certificateHandler: (Bool) -> Void) {
            // TODO security implementation
        }
        
        @objc func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
            if state == .NotConnected {
                // this should be the last reference to self so it should destroy it
                session.delegate = nil
                activeSessions.remove(self)
                print("Peer \(peerID.displayName) closed info session")
            }
        }
    }
    
    /// If we are unknown to the remote peer, it invites us into it's download session which we associate with our upload session.
    private final class PeerInfoUploadSessionManager: MCSessionDelegateAdapter {
        
        init(fromPeer peerID: MCPeerID, invitationHandler: (Bool, MCSession) -> Void) {
            super.init()
            invitationHandler(true, session)
        }
        
        // MARK: MCSessionDelegate
        
        override func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
            super.session(session, peer: peerID, didChangeState: state)
            switch state {
            case .Connected:
                let data = NSKeyedArchiver.archivedDataWithRootObject(NetworkPeerInfo(peer: UserPeerInfo.instance.peer))
                sendData(data, toPeers: [peerID])
            case .Connecting:
                break
            case .NotConnected:
                break
            }
        }
    }
    
    /// If the remote peer is unknown, it invited into the download session of the local peer.
    private final class PeerInfoDownloadSessionHandler: MCSessionDelegateAdapter {
        
        init?(forPeer: MCPeerID) {
            guard let browser = RemotePeerManager.sharedManager.btBrowser else { return nil }
            super.init()
            
            browser.invitePeer(forPeer, toSession: session, withContext: RemotePeerManager.PeerInfoSessionKey.dataUsingEncoding(NSASCIIStringEncoding)!, timeout: RemotePeerManager.InvitationTimeout)
        }
        
        // MARK: MCSessionDelegate
        
        /// Stores new LocalPeerInfo data and ignores all other data. Stays in session until the LocalPeerInfo is received.
        override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
            guard let info = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? NetworkPeerInfo else { return }
            
            RemotePeerManager.sharedManager.cachedPeers[peerID] = LocalPeerInfo(peer: info.peer)
            NSNotificationCenter.defaultCenter().postNotificationName(RemotePeerManager.PeerInfoLoadedNotification, object: self, userInfo: [RemotePeerManager.PeerIDKey : info.peer.peerID])
            
            session.disconnect()
        }
    }
    
    /// If the remote peer is unknown, it invited into the download session of the local peer.
    private final class PictureDownloadSessionHandler: MCSessionDelegateAdapter {
        
        init?(peerID: MCPeerID) {
            guard let browser = RemotePeerManager.sharedManager.btBrowser else { return nil }
            super.init()
            
            browser.invitePeer(peerID, toSession: session, withContext: RemotePeerManager.PictureSessionKey.dataUsingEncoding(NSASCIIStringEncoding)!, timeout: RemotePeerManager.InvitationTimeout)
        }
        
        // MARK: MCSessionDelegate
        
        override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
            guard let peerInfo = RemotePeerManager.sharedManager.cachedPeers[peerID] else {
                session.disconnect()
                return
            }
            guard let image = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? UIImage else { return }
            
            peerInfo.picture = image
            dispatch_async(dispatch_get_main_queue()) {
                RemotePeerManager.sharedManager.loadingPictures.remove(peerID)
                NSNotificationCenter.defaultCenter().postNotificationName(RemotePeerManager.PictureLoadedNotification, object: self, userInfo: [RemotePeerManager.PeerIDKey : peerID])
            }
            
            session.disconnect()
        }
    }
    
    private final class PictureUploadSessionManager: MCSessionDelegateAdapter {
        
        init(fromPeer peerID: MCPeerID, invitationHandler: (Bool, MCSession) -> Void) {
            super.init()
            invitationHandler(true, session)
        }
        
        // MARK: MCSessionDelegate
        
        override func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
            super.session(session, peer: peerID, didChangeState: state)
            switch state {
            case .Connected:
                let data = NSKeyedArchiver.archivedDataWithRootObject(UserPeerInfo.instance.picture!)
                sendData(data, toPeers: [peerID])
            case .Connecting:
                break
            case .NotConnected:
                break
            }
        }
    }
    
    /// If the remote peer is unknown, it invited into the download session of the local peer.
    private final class PinSessionHandler: MCSessionDelegateAdapter {
        
        init?(peerID: MCPeerID) {
            guard let browser = RemotePeerManager.sharedManager.btBrowser else { return nil }
            super.init()
            
            browser.invitePeer(peerID, toSession: session, withContext: RemotePeerManager.PinSessionKey.dataUsingEncoding(NSASCIIStringEncoding)!, timeout: RemotePeerManager.InvitationTimeout)
        }
        
        // MARK: MCSessionDelegate
        
        override func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
            super.session(session, peer: peerID, didChangeState: state)
            switch state {
            case .Connected:
                let data = NSKeyedArchiver.archivedDataWithRootObject(RemotePeerManager.PinSessionKey)
                sendData(data, toPeers: [peerID])
            case .Connecting:
                break
            case .NotConnected:
                break
            }
        }
        
        override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
            guard RemotePeerManager.sharedManager.pinnedPeers.indexForKey(peerID) != nil else { return }
            guard NSKeyedUnarchiver.unarchiveObjectWithData(data) as? String == "ack" else { return }
            
            RemotePeerManager.sharedManager.pinnedPeers[peerID] = true
            archiveObjectInUserDefs(RemotePeerManager.sharedManager.pinnedPeers as NSDictionary, forKey: RemotePeerManager.PinnedPeersKey)
            session.disconnect()
        }
    }
    
    private final class PinnedSessionManager: MCSessionDelegateAdapter {
        
        init(fromPeer peerID: MCPeerID, invitationHandler: (Bool, MCSession) -> Void) {
            super.init()
            invitationHandler(true, session)
        }
        
        // MARK: MCSessionDelegate
        
        override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
            guard NSKeyedUnarchiver.unarchiveObjectWithData(data) as? String == RemotePeerManager.PinSessionKey else { return }
            
            let ackData = NSKeyedArchiver.archivedDataWithRootObject("ack")
            sendData(ackData, toPeers: [peerID])
            
            dispatch_async(dispatch_get_main_queue()) {
                RemotePeerManager.sharedManager.pinnedByPeers.insert(peerID)
                archiveObjectInUserDefs(RemotePeerManager.sharedManager.pinnedByPeers as NSSet, forKey: RemotePeerManager.PinnedByPeersKey)
                if RemotePeerManager.sharedManager.pinnedPeers.indexForKey(peerID) != nil {
                    RemotePeerManager.sharedManager.pinMatchOccured(peerID)
                }
            }
        }
    }
}