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
    static private let PeersMetKey = "PeersMet"
    
    /// Identifies a MCSession. Is sent via the context info.
    enum SessionKey: String {
        /// Session which transfers LocalPeerInfo objects.
        case peerInfo
        /// Session key for transmitting portrait images.
        case picture
        /// Session key for populating pin status.
        case pin
        
        init?(rawData: Data) {
            guard let rawString = String(data: rawData, encoding: String.Encoding.ascii) else { return nil }
            self.init(rawValue: rawString)
        }
        
        var rawData: Data { return rawValue.data(using: String.Encoding.ascii)! }
    }
    
    enum NetworkNotification: String {
        case connectionChangedState
        case peerAppeared, peerDisappeared
        case peerInfoLoaded, peerInfoLoadFailed
        case pictureLoaded, pictureLoadFailed
        case pinned, pinningStarted, pinFailed
        case pinMatch
        
        func addObserver(usingBlock block: @escaping (Notification) -> Void) -> NSObjectProtocol {
            return NotificationCenter.addObserverOnMain(self.rawValue, usingBlock: block)
        }
        
        func post(_ peerID: MCPeerID?) {
            NotificationCenter.default.post(name: Notification.Name(rawValue: self.rawValue), object: RemotePeerManager.shared, userInfo: peerID != nil ? [NetworkNotificationKey.peerID.rawValue : peerID!] : nil)
        }
    }
    
    enum NetworkNotificationKey: String {
        case peerID
    }
    
    static let shared = RemotePeerManager()
	
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
            // writing peersMet here is a good choice, since we will stop peering before the app is quit and also this method won't get called often and the peers met are not that critical
            UserDefaults.standard.set(peersMet, forKey:RemotePeerManager.PeersMetKey)
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
    
    lazy var peersMet = UserDefaults.standard.integer(forKey: RemotePeerManager.PeersMetKey)
    
    func isPeerPinned(_ peerID: MCPeerID) -> Bool {
        return pinnedPeers.contains(peerID)
    }
    
    func hasPinMatch(_ peerID: MCPeerID) -> Bool {
        return isPeerPinned(peerID) && pinnedByPeers.contains(peerID)
    }
    
    func loadPicture(of peer: PeerInfo, delegate: PotraitLoadingDelegate?) {
        if peer.hasPicture && peer.picture == nil && peer != UserPeerInfo.instance.peer {
            if isPictureLoading(of: peer.peerID) {
                guard let d = delegate else { return }
                PictureDownloadSessionHandler.setPictureLoadingDelegate(of: peer.peerID, delegate: d)
            } else {
                let handler = PictureDownloadSessionHandler(peerID: peer.peerID, btBrowser: btBrowser, delegate: delegate)
                assert(handler != nil)
            }
        }
    }
    
    func isPictureLoading(of peerID: MCPeerID) -> Bool {
        return PictureDownloadSessionHandler.isPictureLoading(of: peerID)
    }
    
    func getPictureLoadFraction(of peerID: MCPeerID) -> Double {
        return PictureDownloadSessionHandler.getPictureLoadFraction(of: peerID)
    }
    
    func isPeerInfoLoading(of peerID: MCPeerID) -> Bool {
        return PeerInfoDownloadSessionHandler.isPeerInfoLoading(of: peerID)
    }
    
    func setPictureLoadingDelegate(of peerID: MCPeerID, delegate: PotraitLoadingDelegate) {
        return PictureDownloadSessionHandler.setPictureLoadingDelegate(of: peerID, delegate: delegate)
    }
    
    func isPinning(_ peerID: MCPeerID) -> Bool {
        return PinSessionHandler.isPinning(peerID)
    }
    
    func getPeerInfo(of peerID: MCPeerID, download: Bool = false) -> PeerInfo? {
        if let ret = cachedPeers[peerID]?.peer {
            return ret
        } else if download && peering && !PeerInfoDownloadSessionHandler.isPeerInfoLoading(of: peerID) {
            let handler = PeerInfoDownloadSessionHandler(peerID: peerID, btBrowser: btBrowser)
            assert(handler != nil)
        }
        return nil
    }
    
    func pin(_ peerID: MCPeerID) {
        guard !pinnedPeers.contains(peerID) else { return }
        
        WalletController.requestPin { (confirmation) in
            _ = PinSessionHandler(peerID: peerID, btBrowser: self.btBrowser, confirmation: confirmation)
            NetworkNotification.pinningStarted.post(peerID)
        }
    }
    
    func clearCache() {
        cachedPeers.removeAll()
    }
    
    func sessionHandlerDidLoad(_ peerInfo: NetworkPeerInfo) {
        cachedPeers[peerInfo.peer.peerID] = LocalPeerInfo(peer: peerInfo.peer)
        NetworkNotification.peerInfoLoaded.post(peerInfo.peer.peerID)
    }
    
    func sessionHandlerDidLoad(_ picture: UIImage, of peerID: MCPeerID) {
        guard let peerInfo = cachedPeers[peerID] else { return }
        
        peerInfo.picture = picture
        NetworkNotification.pictureLoaded.post(peerID)
    }
    
    func sessionHandlerDidPin(_ peerID: MCPeerID) {
        pinnedPeers.insert(peerID)
        archiveObjectInUserDefs(pinnedPeers.set as NSSet, forKey: RemotePeerManager.PinnedPeersKey)
        if RemotePeerManager.shared.pinnedByPeers.contains(peerID) {
            RemotePeerManager.shared.pinMatchOccured(peerID)
        }
        
        NetworkNotification.pinned.post(peerID)
    }
    
    func sessionHandlerReceivedPin(from peerID: MCPeerID) {
        pinnedByPeers.insert(peerID)
        archiveObjectInUserDefs(pinnedByPeers.set as NSSet, forKey: RemotePeerManager.PinnedByPeersKey)
        if pinnedPeers.contains(peerID) {
            pinMatchOccured(peerID)
        }
    }
	
	// MARK: - MCNearbyServiceAdvertiserDelegate
	
	@objc func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer: Error) {
        // here one could log the error and send it via internet, but in a very very future
		peering = false
	}
	
	@objc func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        guard let sessionKeyData = context else {
            invitationHandler(false, MCSession(peer: UserPeerInfo.instance.peer.peerID))
            assertionFailure()
            return
        }
        guard let sessionKey = SessionKey(rawData: sessionKeyData) else {
            invitationHandler(false, MCSession(peer: UserPeerInfo.instance.peer.peerID))
            assertionFailure()
            return
        }
        
        switch sessionKey {
        case .peerInfo:
            _ = PeerInfoUploadSessionManager(from: peerID, invitationHandler: invitationHandler)
        case .picture:
            _ = PictureUploadSessionManager(from: peerID, invitationHandler: invitationHandler)
        case .pin:
            _ = PinnedSessionManager(from: peerID, invitationHandler: invitationHandler)
        }
	}
	
	// MARK: MCNearbyServiceBrowserDelegate
	
	@objc func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
		// here one could log the error and send it via internet, but in a very very future
        peering = false
	}
	
    @objc func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard !_availablePeers.contains(peerID) else { return }
        
        peersMet = peersMet + 1
        _availablePeers.insert(peerID)
        self.peerAppeared(peerID)
	}
	
	@objc func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		_availablePeers.remove(peerID)
		self.peerDisappeared(peerID)
    }
    
    // MARK: Private Methods
    
    private override init() {
        let nsPinned: NSSet? = unarchiveObjectFromUserDefs(RemotePeerManager.PinnedPeersKey)
        pinnedPeers = SynchronizedSet(set: nsPinned as? Set<MCPeerID> ?? Set())
        let nsPinnedBy: NSSet? = unarchiveObjectFromUserDefs(RemotePeerManager.PinnedByPeersKey)
        pinnedByPeers = SynchronizedSet(set: nsPinnedBy as? Set<MCPeerID> ?? Set())
    }
    
    private func peerAppeared(_ peerID: MCPeerID) {
        NetworkNotification.peerAppeared.post(peerID)
    }
    
    private func peerDisappeared(_ peerID: MCPeerID) {
        NetworkNotification.peerDisappeared.post(peerID)
    }
    
    private func connectionChangedState() {
        NetworkNotification.connectionChangedState.post(nil)
    }
    
    private func pinMatchOccured(_ peerID: MCPeerID) {
        NetworkNotification.pinMatch.post(peerID)
    }
}
