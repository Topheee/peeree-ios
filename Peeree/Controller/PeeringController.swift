//
//  PeeringController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 04.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation

public protocol RemotePeering {
    var peersMet: Int { get }
    var isBluetoothOn: Bool { get }
    func getPeerInfo(of peerID: PeerID) -> PeerInfo?
    func loadPeerInfo(of peerID: PeerID) -> Progress?
    func isPeerInfoLoading(of peerID: PeerID) -> Progress?
    func loadPicture(of peer: PeerInfo) -> Progress?
    func isPictureLoading(of peerID: PeerID) -> Progress?
    func isPinning(_ peerID: PeerID) -> Bool
}

//public protocol LocalPeering {
//}

/// The PeeringController singleton is the app's interface to the bluetooth network as well as to information about pinned peers.
public final class PeeringController : LocalPeerManagerDelegate, RemotePeerManagerDelegate {
    static private let PinnedPeersKey = "PinnedPeers"
    static private let PinnedByPeersKey = "PinnedByPeers"
    
    public static let shared = PeeringController()
    
    public enum NetworkNotificationKey: String {
        case peerID
    }
    
    public enum NetworkNotification: String {
        case connectionChangedState
        case peerAppeared, peerDisappeared
        case pinned, pinningStarted, pinFailed
        case pinMatch
        
        public func addObserver(usingBlock block: @escaping (Notification) -> Void) -> NSObjectProtocol {
            return NotificationCenter.addObserverOnMain(self.rawValue, usingBlock: block)
        }
        
        func post(_ peerID: PeerID?) {
            NotificationCenter.default.post(name: Notification.Name(rawValue: self.rawValue), object: PeeringController.shared, userInfo: peerID != nil ? [NetworkNotificationKey.peerID.rawValue : peerID!] : nil)
        }
    }
    
    private let _local = LocalPeerManager()
    private let _remote = RemotePeerManager()
    
    /// stores acknowledged pinned peers
    private var pinnedPeers = SynchronizedSet<PeerID>()
    // maybe encrypt these on disk so no one can read out their display names
    private var pinnedByPeers = SynchronizedSet<PeerID>()
    
    private var pinningConfirmations = SynchronizedDictionary<PeerID, WalletController.PinConfirmation>()
    
    public let remote: RemotePeering
//    public let local: LocalPeering
    
    public var availablePeers: [PeerID] {
        return _remote.availablePeers
    }
    
    public var peering: Bool {
        get {
            return _local.isAdvertising //|| _remote.isScanning
        }
        set {
            if newValue {
                _local.startAdvertising()
                _remote.scan()
            } else {
                _local.stopAdvertising()
                _remote.stopScan()
            }
        }
    }
    
    public func hasPinMatch(_ peerID: PeerID) -> Bool {
        return isPinned(peerID) && isPinned(by: peerID)
    }
    
    public func isPinned(by peerID: PeerID) -> Bool {
        return pinnedByPeers.contains(peerID)
    }
    
    public func pin(_ peerID: PeerID) {
        guard !isPinned(peerID) else { return }
        guard _remote.availablePeers.contains(peerID) else { return }
        guard !(pinningConfirmations.contains { $0.0 == peerID }) else { return }
        
        WalletController.requestPin { confirmation in
            self.pinningConfirmations[peerID] = confirmation
            self._remote.pin(peerID)
            NetworkNotification.pinningStarted.post(peerID)
        }
    }
    
    // MARK: LocalPeerManagerDelegate
    
    func advertisingStarted() {
        _remote.scan()
        connectionChangedState()
    }
    
    func advertisingStopped() {
        _remote.stopScan()
        connectionChangedState()
    }
    
    func receivedPin(from peerID: PeerID) {
        pinnedByPeers.accessQueue.async {
            guard !self.pinnedByPeers.set.contains(peerID) else { return }
            self.pinnedByPeers.set.insert(peerID)
            // access the set on the queue to ensure the last peerID is also included ...
            // ... and besides get a smoother UI
            archiveObjectInUserDefs(self.pinnedByPeers.set as NSSet, forKey: PeeringController.PinnedByPeersKey)
            
            if self.pinnedPeers.contains(peerID) {
                self.pinMatchOccured(peerID)
            }
        }
    }
    
    // MARK: RemotePeerManagerDelegate
    
//    func scanningStopped() {
//        if local.isAdvertising {
//            local.stopAdvertising()
//            connectionChangedState()
//        }
//    }
    
    func peerAppeared(_ peerID: PeerID) {
        if _remote.getPeerInfo(of: peerID) == nil {
            _ = _remote.loadPeerInfo(of: peerID)
        }
        NetworkNotification.peerAppeared.post(peerID)
    }
    
    func peerDisappeared(_ peerID: PeerID) {
        NetworkNotification.peerDisappeared.post(peerID)
    }
    
    func didPin(_ peerID: PeerID) {
        guard let confirmation = pinningConfirmations.removeValueForKey(peerID) else {
            assertionFailure("Pinned \(peerID) without confirmation. Refused.")
            return
        }
        
        WalletController.redeem(confirmation: confirmation)
        pinnedPeers.accessQueue.async {
            self.pinnedPeers.set.insert(peerID)
            // access the set on the queue to ensure the last peerID is also included ...
            // ... and besides get a smoother UI
            archiveObjectInUserDefs(self.pinnedPeers.set as NSSet, forKey: PeeringController.PinnedPeersKey)
        }
        if pinnedByPeers.contains(peerID) {
            pinMatchOccured(peerID)
        }
        
        NetworkNotification.pinned.post(peerID)
    }
    
    func didFailPin(_ peerID: PeerID) {
        _ = pinningConfirmations.removeValueForKey(peerID)
        NetworkNotification.pinFailed.post(peerID)
    }
    
    func isPinned(_ peerID: PeerID) -> Bool {
        return pinnedPeers.contains(peerID)
    }
    
    // MARK: Private Methods
    
    private init() {
        remote = _remote
//        local = _local
        let nsPinnedBy: NSSet? = unarchiveObjectFromUserDefs(PeeringController.PinnedByPeersKey)
        pinnedByPeers = SynchronizedSet(set: nsPinnedBy as? Set<PeerID> ?? Set())
        let nsPinned: NSSet? = unarchiveObjectFromUserDefs(PeeringController.PinnedPeersKey)
        pinnedPeers = SynchronizedSet(set: nsPinned as? Set<PeerID> ?? Set())
        _remote.delegate = self
        _local.delegate = self
    }
    
    private func pinMatchOccured(_ peerID: PeerID) {
//        DispatchQueue.main.async { // PERFORMACE do we need this?
            NetworkNotification.pinMatch.post(peerID)
//        }
    }
    
    private func connectionChangedState() {
        NetworkNotification.connectionChangedState.post(nil)
    }
}
