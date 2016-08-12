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
    
    static private let PinnedPeersKey = "PinnedPeers"
    static private let PinnedByPeersKey = "PinnedByPeers"
    
    /// Identifies a MCSession. Is sent via the context info.
    enum SessionKey: String {
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
    private var cachedPeers = SynchronizedDictionary<MCPeerID, LocalPeerInfo>()
    
	/// Bluetooth network handlers.
    private var btAdvertiser: MCNearbyServiceAdvertiser?
    private var btBrowser: MCNearbyServiceBrowser?
    
	/*
	 *	All remote peers the app is currently connected to. This property is immediatly updated when a new connection is set up or an existing is cut off.
	 */
	private var _availablePeers = SynchronizedSet<MCPeerID>() // TODO convert into NSOrderedSet to not always confuse the order of the browse view
    
    /// stores acknowledged pinned peers
    private var pinnedPeers = SynchronizedSet<MCPeerID>()
    // maybe encrypt these on disk so no one can read out their display names
    private var pinnedByPeers = SynchronizedSet<MCPeerID>()
    
    var availablePeers: SynchronizedSet<MCPeerID> {
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
                self.connectionChangedState()
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
        if forPeer.hasPicture && forPeer.picture == nil && !isPictureLoading(forPeer.peerID) {
            let handler = PictureDownloadSessionHandler(peerID: forPeer.peerID, btBrowser: btBrowser)
            assert(handler != nil)
        }
    }
    
    func isPictureLoading(ofPeer: MCPeerID) -> Bool {
        return PictureDownloadSessionHandler.isPictureLoading(ofPeer)
    }
    
    func getPeerInfo(forPeer peerID: MCPeerID, download: Bool = false) -> PeerInfo? {
        if let ret = cachedPeers[peerID]?.peer {
            return ret
        } else if download && peering {
            let handler = PeerInfoDownloadSessionHandler(peerID: peerID, btBrowser: btBrowser)
            assert(handler != nil)
        }
        return nil
    }
    
    func pinPeer(peerID: MCPeerID) {
        guard !pinnedPeers.contains(peerID) else { return }
        
        WalletController.requestPin { (confirmation) in
            _ = PinSessionHandler(peerID: peerID, btBrowser: self.btBrowser, confirmation: confirmation)
        }
    }
    
    func sessionHandlerDidLoad(peerInfo: NetworkPeerInfo) {
        cachedPeers[peerInfo.peer.peerID] = LocalPeerInfo(peer: peerInfo.peer)
        NetworkNotification.PeerInfoLoaded.post(peerInfo.peer.peerID)
    }
    
    func sessionHandlerDidLoad(picture: UIImage, ofPeer peerID: MCPeerID) {
        guard let peerInfo = cachedPeers[peerID] else { return }
        
        peerInfo.picture = picture
        NetworkNotification.PictureLoaded.post(peerID)
    }
    
    func sessionHandlerDidPin(peerID: MCPeerID) {
        pinnedPeers.insert(peerID)
        archiveObjectInUserDefs(pinnedPeers.set as NSSet, forKey: RemotePeerManager.PinnedPeersKey)
        if !RemotePeerManager.sharedManager.pinnedPeers.contains(peerID) && RemotePeerManager.sharedManager.pinnedByPeers.contains(peerID) {
            RemotePeerManager.sharedManager.pinMatchOccured(peerID)
        }
        
        NetworkNotification.Pinned.post(peerID)
    }
    
    func sessionHandlerReceivedPin(from peerID: MCPeerID) {
        pinnedByPeers.insert(peerID)
        archiveObjectInUserDefs(pinnedByPeers.set as NSSet, forKey: RemotePeerManager.PinnedByPeersKey)
        if pinnedPeers.contains(peerID) {
            pinMatchOccured(peerID)
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
        pinnedPeers = SynchronizedSet(set: nsPinned as? Set<MCPeerID> ?? Set())
        let nsPinnedBy: NSSet? = unarchiveObjectFromUserDefs(RemotePeerManager.PinnedByPeersKey)
        pinnedByPeers = SynchronizedSet(set: nsPinnedBy as? Set<MCPeerID> ?? Set())
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
}