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
final class RemotePeerManager: NSObject, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, RemotePeerManagerDelegate {
	static private let kDiscoveryServiceID = "peeree-discover"
	static private let kInvitationTimeout: NSTimeInterval = 5.0
    
    /// Identifies a MCSession as a session which transfers LocalPeerInfo objects.
    static private let kPeerInfoSessionKey = "PeerInfoSession"
    /// Session key for transmitting portrait images.
    static private let kPictureSessionKey = "PictureSession"
    
    static let sharedManager = RemotePeerManager()
	
	/*
	 *	Since bluetooth connections are not very reliable, all peers and their images are cached for a reasonable amount of time (at least 30 Minutes).
     * TODO maybe use some standardized caching API for this?
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
	private var pinnedPeers: [LocalPeerInfo] = []
    
    var availablePeers: Set<MCPeerID> {
        return _availablePeers
    }
    
	
    /// If you set this property to nil, it is automatically re-set to the shared delegate.
    var delegate: RemotePeerManagerDelegate! = AppDelegate.sharedDelegate {
        didSet {
            if delegate == nil {
                delegate = AppDelegate.sharedDelegate
            }
        }
    }
    
    var peering: Bool {
        get {
            return btAdvertiser != nil && btBrowser != nil
        }
        set {
            guard newValue != peering else { return }
            if newValue {
                let peerID = UserPeerInfo.instance.peerID
                
                btAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: RemotePeerManager.kDiscoveryServiceID)
                btAdvertiser!.delegate = self
                btBrowser = MCNearbyServiceBrowserMock(peer: peerID, serviceType: RemotePeerManager.kDiscoveryServiceID)
                btBrowser!.delegate = self
                
                self.connectionChangedState(newValue)
                
                btAdvertiser?.startAdvertisingPeer()
                btBrowser?.startBrowsingForPeers()
            } else {
                btAdvertiser?.stopAdvertisingPeer()
                btBrowser?.stopBrowsingForPeers()
                btAdvertiser = nil
                btBrowser = nil
                self.connectionChangedState(newValue)
                // TODO cancel and close all sessions. Seems, that we have to store them somewhere (maybe in the availablePeers tuple)
            }
        }
    }
    
    func loadPicture(forPeer: SerializablePeerInfo, callback: (SerializablePeerInfo) -> Void) {
        if forPeer.hasPicture && forPeer.picture == nil && !isPictureLoading(forPeer.peerID) {
            loadingPictures.insert(forPeer.peerID)
            let _ = PictureDownloadSessionHandler(peerID: forPeer.peerID, callback: callback)
        }
    }
    
    func isPictureLoading(ofPeer: MCPeerID) -> Bool {
        return !loadingPictures.contains(ofPeer)
    }
	
	func getPeerInfo(forPeer peerID: MCPeerID, download: Bool = false) -> SerializablePeerInfo? {
		if let ret = cachedPeers[peerID] {
			return ret
		} else if download {
            // TODO figure out whether this thing is remaining alive
            let _ = PeerInfoDownloadSessionHandler(forPeer: peerID)
        }
		return nil
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
        case RemotePeerManager.kPeerInfoSessionKey:
            PeerInfoUploadSessionManager.sharedManager.handleInvitation(fromPeer: peerID, invitationHandler: invitationHandler)
        case RemotePeerManager.kPictureSessionKey:
            PictureUploadSessionManager.sharedManager.handleInvitation(fromPeer: peerID, invitationHandler: invitationHandler)
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
        // TODO make use of discoveryInfo, but update the information provided within it, when the user taps on a peer or at least when he wants to pin someone, since we cannot trust the information provided in discoveryInfo I think
		guard !_availablePeers.contains(peerID) else { return }
		
		_availablePeers.insert(peerID)
		
		self.remotePeerAppeared(peerID)
		
		if cachedPeers[peerID] == nil {
			// immediatly begin to retrieve downloading information
			// TODO if this needs too much energy, disable this feature or make it optional. Note, that in this case filtering is not possible (except, we use the discovery info dict)
			let _ = PeerInfoDownloadSessionHandler(forPeer: peerID)
		}
	}
	
	@objc func browser(browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		_availablePeers.remove(peerID)
		self.remotePeerDisappeared(peerID)
    }
    
    // MARK: RemotePeerManagerDelegate
    
    func remotePeerAppeared(peer: MCPeerID) {
        dispatch_async(dispatch_get_main_queue()) {
            self.delegate.remotePeerAppeared(peer)
        }
    }
    
    func remotePeerDisappeared(peer: MCPeerID) {
        dispatch_async(dispatch_get_main_queue()) {
            self.delegate.remotePeerDisappeared(peer)
        }
    }
    
    func connectionChangedState(nowOnline: Bool) {
        dispatch_async(dispatch_get_main_queue()) {
            self.delegate.connectionChangedState(nowOnline)
        }
    }
    
    func peerInfoLoaded(peerInfo: SerializablePeerInfo) {
        dispatch_async(dispatch_get_main_queue()) {
            self.delegate.peerInfoLoaded(peerInfo)
        }
    }
    
    // MARK: - Private classes
    
    private class MCSessionDelegateAdapter: NSObject, MCSessionDelegate {
        
        lazy var session = MCSession(peer: UserPeerInfo.instance.peerID, securityIdentity: nil, encryptionPreference: .Required)
        
        // ignored
        @objc func session(session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, withProgress progress: NSProgress) {}
        @objc func session(session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, atURL localURL: NSURL, withError error: NSError?) {}
        @objc func session(session: MCSession, didReceiveStream stream: NSInputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
        @objc func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {}
        
        @objc func session(session: MCSession, didReceiveCertificate certificate: [AnyObject]?, fromPeer peerID: MCPeerID, certificateHandler: (Bool) -> Void) {
            // TODO security implementation
        }
        
        @objc func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {}
    }
    
    /// If we are unknown to the remote peer, it invites us into it's download session which we associate with our upload session.
    private final class PeerInfoUploadSessionManager: MCSessionDelegateAdapter {
        
        static let sharedManager = PeerInfoUploadSessionManager()
        
        func handleInvitation(fromPeer peerID: MCPeerID, invitationHandler: (Bool, MCSession) -> Void) {
            session.delegate = self
            invitationHandler(true, session)
        }
        
        // MARK: MCSessionDelegate
        
        @objc override func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
            switch state {
            case .Connected:
                // TODO test, whether the casts works as expected (thats, only encode the SerializablePeerInfo subset)
                let data = NSKeyedArchiver.archivedDataWithRootObject(UserPeerInfo.instance as SerializablePeerInfo)
                do {
                    try session.sendData(data, toPeers: [peerID], withMode: .Reliable)
                } catch let error as NSError {
                    // TODO handle send fails
                    print("Info sending failed: \(error)")
                } catch let error as NSErrorPointer {
                    // TODO handle send fails
                    print("Info sending failed: \(error.memory)")
                }
            case .Connecting:
                break
            case .NotConnected:
                print("Peer \(peerID.displayName) closed info session")
                break
            }
        }
    }
    
    /// If the remote peer is unknown, it invited into the download session of the local peer.
    private final class PeerInfoDownloadSessionHandler: MCSessionDelegateAdapter {
        
        init(forPeer: MCPeerID) {
            super.init()
            assert(RemotePeerManager.sharedManager.btBrowser != nil, "The PeerInfoSessionManager should only be instantiated with an active service browser.")
            
            session.delegate = self
            RemotePeerManager.sharedManager.btBrowser?.invitePeer(forPeer, toSession: session, withContext: RemotePeerManager.kPeerInfoSessionKey.dataUsingEncoding(NSASCIIStringEncoding)!, timeout: RemotePeerManager.kInvitationTimeout)
        }
        
        // MARK: MCSessionDelegate
        
        /**
         * Stores new LocalPeerInfo data and ignores all other data. Stays in session until the LocalPeerInfo is received.
         */
        @objc override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
            guard let info = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? LocalPeerInfo else { return }
            
            RemotePeerManager.sharedManager.cachedPeers[peerID] = info
            RemotePeerManager.sharedManager.peerInfoLoaded(info)
            
            session.disconnect()
        }
    }
    
    /// If the remote peer is unknown, it invited into the download session of the local peer.
    private final class PictureDownloadSessionHandler: MCSessionDelegateAdapter {
        
        private let callback: (SerializablePeerInfo) -> Void
        
        init(peerID: MCPeerID, callback: (SerializablePeerInfo) -> Void) {
            self.callback = callback
            super.init()
            assert(RemotePeerManager.sharedManager.btBrowser != nil, "The PeerInfoSessionManager should only be instantiated with an active service browser.")
            
            session.delegate = self
            RemotePeerManager.sharedManager.btBrowser?.invitePeer(peerID, toSession: session, withContext: RemotePeerManager.kPictureSessionKey.dataUsingEncoding(NSASCIIStringEncoding)!, timeout: RemotePeerManager.kInvitationTimeout)
        }
        
        // MARK: MCSessionDelegate
        
        @objc override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
            guard let peerInfo = RemotePeerManager.sharedManager.cachedPeers[peerID] else {
                session.disconnect()
                return
            }
            guard let image = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? UIImage else { return }
            
            peerInfo.picture = image
            dispatch_async(dispatch_get_main_queue()) {
                self.callback(peerInfo)
            }
            
            session.disconnect()
        }
    }
    
    private final class PictureUploadSessionManager: MCSessionDelegateAdapter {
        
        static let sharedManager = PictureUploadSessionManager()
        
        func handleInvitation(fromPeer peerID: MCPeerID, invitationHandler: (Bool, MCSession) -> Void) {
            session.delegate = self
            invitationHandler(true, session)
        }
        
        // MARK: MCSessionDelegate
        
        @objc override func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
            switch state {
            case .Connected:
                // TODO test, whether the casts works as expected (thats, only encode the LocalPeerInfo subset)
                let data = NSKeyedArchiver.archivedDataWithRootObject(UserPeerInfo.instance.picture!)
                do {
                    try session.sendData(data, toPeers: [peerID], withMode: .Reliable)
                } catch let error as NSError {
                    // TODO handle send fails
                    print("Picture sending failed: \(error)")
                } catch let error as NSErrorPointer {
                    // TODO handle send fails
                    print("Picture sending failed: \(error.memory)")
                }
                
                break
            case .Connecting:
                break
            case .NotConnected:
                print("Peer \(peerID.displayName) closed picture session")
                break
            }
        }
    }
}

// MARK: - RemotePeerManagerDelegate

protocol RemotePeerManagerDelegate {
	func remotePeerAppeared(peerID: MCPeerID)
	func remotePeerDisappeared(peerID: MCPeerID)
    func connectionChangedState(nowOnline: Bool)
    func peerInfoLoaded(peer: SerializablePeerInfo)
}