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
    
    /// Identifies a MCSession. Is sent via the context info.
    private enum SessionKey: String {
        /// Session which transfers LocalPeerInfo objects.
        case PeerInfo
        /// Session key for transmitting portrait images.
        case Picture
        /// Session key for populating pin status.
        case Pin
    }
    
    enum NetworkNotification: String {
        case ConnectionChangedState
        case RemotePeerAppeared, RemotePeerDisappeared
        case PeerInfoLoaded, PeerInfoLoadFailed
        case PictureLoaded, PictureLoadFailed
        case Pinned, PinFailed
        case PinMatch
        
        func addObserver(usingBlock block: (NSNotification) -> Void) -> NSObjectProtocol {
            return NSNotificationCenter.addObserverOnMain(self.rawValue, usingBlock: block)
        }
        
        func post(peerID: MCPeerID?) {
            NSNotificationCenter.defaultCenter().postNotificationName(self.rawValue, object: RemotePeerManager.sharedManager, userInfo: peerID != nil ? [NetworkNotificationKey.PeerID.rawValue : peerID!] : nil)
        }
    }
    
    enum NetworkNotificationKey: String {
        case PeerID
    }
    
    static let sharedManager = RemotePeerManager()
	
	///	Since bluetooth connections are not very reliable, all peers and their images are cached.
    private var cachedPeers: [MCPeerID : LocalPeerInfo] = [:]
    private var loadingPictures: Set<MCPeerID> = Set()
    
	/// Bluetooth network handlers.
    private var btAdvertiser: MCNearbyServiceAdvertiser?
    private var btBrowser: MCNearbyServiceBrowser?
    
	/*
	 *	All remote peers the app is currently connected to. This property is immediatly updated when a new connection is set up or an existing is cut off.
	 */
	private var _availablePeers = Set<MCPeerID>() // TODO convert into NSOrderedSet to not always confuse the order of the browse view
    
    /// stores acknowledged pinned peers
    private var pinnedPeers: Set<MCPeerID>
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
                #if OFFLINE
                    btBrowser = MCNearbyServiceBrowserMock(peer: peerID, serviceType: RemotePeerManager.DiscoveryServiceID)
                #else
                    btBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: RemotePeerManager.DiscoveryServiceID)
                #endif
                
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
        return pinnedPeers.contains(peerID)
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
            let handler = PeerInfoDownloadSessionHandler(peerID: peerID)
            assert(handler != nil)
        }
        return nil
    }
    
    func pinPeer(peerID: MCPeerID) {
        guard !pinnedPeers.contains(peerID) else { return }
        
        WalletController.requestPin { (confirmation) in
            _ = PinSessionHandler(peerID: peerID, confirmation: confirmation)
        }
    }
	
	// MARK: - MCNearbyServiceAdvertiserDelegate
	
	@objc func advertiser(advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer: NSError) {
        // here one could log the error and send it via internet, but in a very very future
		peering = false
	}
	
	@objc func advertiser(advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: NSData?, invitationHandler: (Bool, MCSession) -> Void) {
        guard let sessionKeyData = context else { invitationHandler(false, MCSession()); return }
        guard let sessionKeyString = String(data: sessionKeyData, encoding: NSASCIIStringEncoding) else { invitationHandler(false, MCSession()); return }
        guard let sessionKey = SessionKey(rawValue: sessionKeyString) else { invitationHandler(false, MCSession()); return }
        
        switch sessionKey {
        case .PeerInfo:
            _ = PeerInfoUploadSessionManager(fromPeer: peerID, invitationHandler: invitationHandler)
        case .Picture:
            _ = PictureUploadSessionManager(fromPeer: peerID, invitationHandler: invitationHandler)
        case .Pin:
            _ = PinnedSessionManager(fromPeer: peerID, invitationHandler: invitationHandler)
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
	}
	
	@objc func browser(browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		_availablePeers.remove(peerID)
		self.remotePeerDisappeared(peerID)
    }
    
    // MARK: Private Methods
    
    private override init() {
        let nsPinned: NSSet? = unarchiveObjectFromUserDefs(RemotePeerManager.PinnedPeersKey)
        pinnedPeers = nsPinned as? Set<MCPeerID> ?? Set()
        let nsPinnedBy: NSSet? = unarchiveObjectFromUserDefs(RemotePeerManager.PinnedByPeersKey)
        pinnedByPeers = nsPinnedBy as? Set<MCPeerID> ?? Set()
    }
    
    private func remotePeerAppeared(peerID: MCPeerID) {
        NetworkNotification.RemotePeerAppeared.post(peerID)
    }
    
    private func remotePeerDisappeared(peerID: MCPeerID) {
        NetworkNotification.RemotePeerDisappeared.post(peerID)
    }
    
    private func connectionChangedState() {
        NetworkNotification.ConnectionChangedState.post(nil)
    }
    
    private func pinMatchOccured(peerID: MCPeerID) {
        NetworkNotification.PinMatch.post(peerID)
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
            certificateHandler(true)
        }
        
        @objc func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
            if state == .NotConnected {
                // this should be the last reference to self so it should destroy it
                session.delegate = nil
                activeSessions.remove(self)
            }
        }
    }
    
    /// Base class for all session handlers which retrieve information from an remote peers
    private class DownloadSessionDelegate: MCSessionDelegateAdapter {
        private static let MaxAttempts = 3
        private let failNotification: NetworkNotification
        private let peerID: MCPeerID
        private let sessionKeyData: NSData
        private var attempt = 0
        
        var willReconnect: Bool {
            get {
                return attempt < DownloadSessionDelegate.MaxAttempts && RemotePeerManager.sharedManager.peering && RemotePeerManager.sharedManager._availablePeers.contains(peerID)
            }
            set {
                attempt = DownloadSessionDelegate.MaxAttempts
                session.disconnect()
            }
        }
        
        init(peerID: MCPeerID, sessionKey: SessionKey, failNotification: NetworkNotification) {
            self.peerID = peerID
            self.failNotification = failNotification
            sessionKeyData = sessionKey.rawValue.dataUsingEncoding(NSASCIIStringEncoding)!
            super.init()
        }
        
        private func connect() {
            guard let browser = RemotePeerManager.sharedManager.btBrowser else {
                failNotification.post(peerID)
                return
            }
            guard willReconnect else {
                failNotification.post(peerID)
                return
            }
            
            attempt += 1
            browser.invitePeer(peerID, toSession: session, withContext: sessionKeyData, timeout: RemotePeerManager.InvitationTimeout)
        }
        
        private override func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
            switch state {
            case .Connected, .Connecting:
                super.session(session, peer: peerID, didChangeState: state)
            case .NotConnected:
                if willReconnect {
                    connect()
                } else {
                    super.session(session, peer: peerID, didChangeState: state)
                }
            }
            
        }
    }
    
    /// If we are unknown to the remote peer, it invites us into it's download session which we associate with our upload session.
    private final class PeerInfoUploadSessionManager: MCSessionDelegateAdapter {
        
        init(fromPeer peerID: MCPeerID, invitationHandler: (Bool, MCSession) -> Void) {
            super.init()
            invitationHandler(true, session)
        }
        
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
    private final class PeerInfoDownloadSessionHandler: DownloadSessionDelegate {
        
        init?(peerID: MCPeerID) {
            super.init(peerID: peerID, sessionKey: .PeerInfo, failNotification: .PeerInfoLoadFailed)
        }
        
        /// Stores new LocalPeerInfo data and ignores all other data. Stays in session until the LocalPeerInfo is received.
        override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
            guard let info = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? NetworkPeerInfo else { return }
            
            RemotePeerManager.sharedManager.cachedPeers[peerID] = LocalPeerInfo(peer: info.peer)
            NetworkNotification.PeerInfoLoaded.post(peerID)
            
            willReconnect = false
        }
    }
    
    /// If the remote peer is unknown, it invited into the download session of the local peer.
    private final class PictureDownloadSessionHandler: DownloadSessionDelegate {
        
        init?(peerID: MCPeerID) {
            super.init(peerID: peerID, sessionKey: .Picture, failNotification: .PictureLoadFailed)
        }
        
        override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
            guard let peerInfo = RemotePeerManager.sharedManager.cachedPeers[peerID] else {
                willReconnect = false
                return
            }
            guard let image = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? UIImage else { return }
            
            peerInfo.picture = image
            dispatch_async(dispatch_get_main_queue()) {
                RemotePeerManager.sharedManager.loadingPictures.remove(peerID)
                NetworkNotification.PictureLoaded.post(peerID)
            }
            
            willReconnect = false
        }
        
        private override func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
            if state == .NotConnected && !willReconnect {
                RemotePeerManager.sharedManager.loadingPictures.remove(peerID)
            }
            super.session(session, peer: peerID, didChangeState: state)
        }
    }
    
    private final class PictureUploadSessionManager: MCSessionDelegateAdapter {
        
        init(fromPeer peerID: MCPeerID, invitationHandler: (Bool, MCSession) -> Void) {
            super.init()
            invitationHandler(true, session)
        }
        
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
    private final class PinSessionHandler: DownloadSessionDelegate {
        let confirmation: WalletController.PinConfirmation
        
        init?(peerID: MCPeerID, confirmation: WalletController.PinConfirmation) {
            self.confirmation = confirmation
            super.init(peerID: peerID, sessionKey: .Pin, failNotification: .PinFailed)
        }
        
        override func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
            switch state {
            case .Connected:
                let data = NSKeyedArchiver.archivedDataWithRootObject(SessionKey.Pin.rawValue)
                sendData(data, toPeers: [peerID])
            case .Connecting:
                break
            case .NotConnected:
                break
            }
            super.session(session, peer: peerID, didChangeState: state)
        }
        
        override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
            guard NSKeyedUnarchiver.unarchiveObjectWithData(data) as? String == "ack" else { return }
            guard !confirmation.redeemed else {
                willReconnect = false
                return
            }
            
            WalletController.redeem(confirmation)
            RemotePeerManager.sharedManager.pinnedPeers.insert(peerID)
            archiveObjectInUserDefs(RemotePeerManager.sharedManager.pinnedPeers as NSSet, forKey: RemotePeerManager.PinnedPeersKey)
            if !RemotePeerManager.sharedManager.pinnedPeers.contains(peerID) && RemotePeerManager.sharedManager.pinnedByPeers.contains(peerID) {
                RemotePeerManager.sharedManager.pinMatchOccured(peerID)
            }
            
            NetworkNotification.Pinned.post(peerID)
            willReconnect = false
        }
    }
    
    private final class PinnedSessionManager: MCSessionDelegateAdapter {
        
        init(fromPeer peerID: MCPeerID, invitationHandler: (Bool, MCSession) -> Void) {
            super.init()
            invitationHandler(true, session)
        }
        
        override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
            guard NSKeyedUnarchiver.unarchiveObjectWithData(data) as? String == SessionKey.Pin.rawValue else { return }
            
            let ackData = NSKeyedArchiver.archivedDataWithRootObject("ack")
            sendData(ackData, toPeers: [peerID])
            
            dispatch_async(dispatch_get_main_queue()) {
                RemotePeerManager.sharedManager.pinnedByPeers.insert(peerID)
                archiveObjectInUserDefs(RemotePeerManager.sharedManager.pinnedByPeers as NSSet, forKey: RemotePeerManager.PinnedByPeersKey)
                if RemotePeerManager.sharedManager.pinnedPeers.contains(peerID) {
                    RemotePeerManager.sharedManager.pinMatchOccured(peerID)
                }
            }
        }
    }
}