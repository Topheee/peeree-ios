//
//  PeeringController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 04.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation

protocol RemotePeering {
    var peersMet: Int { get }
    var isBluetoothOn: Bool { get }
    func getPeerInfo(of peerID: PeerID) -> PeerInfo?
    func loadPeerInfo(of peerID: PeerID) -> Progress?
    func isPeerInfoLoading(of peerID: PeerID) -> Progress?
    func loadPicture(of peer: PeerInfo) -> Progress?
    func isPictureLoading(of peerID: PeerID) -> Progress?
}

protocol LocalPeering {
    func isPinning(_ peerID: PeerID) -> Bool
}

final class PeeringController : LocalPeerManagerDelegate, RemotePeerManagerDelegate {
    static private let PinnedPeersKey = "PinnedPeers"
    static private let PinnedByPeersKey = "PinnedByPeers"
    
    static let shared = PeeringController()
    
    enum NetworkNotificationKey: String {
        case peerID
    }
    
    enum NetworkNotification: String {
        case connectionChangedState
        case peerAppeared, peerDisappeared
        case pinned, pinningStarted, pinFailed
        case pinMatch
        
        func addObserver(usingBlock block: @escaping (Notification) -> Void) -> NSObjectProtocol {
            return NotificationCenter.addObserverOnMain(self.rawValue, usingBlock: block)
        }
        
        func post(_ peerID: PeerID?) {
            NotificationCenter.default.post(name: Notification.Name(rawValue: self.rawValue), object: PeeringController.shared, userInfo: peerID != nil ? [NetworkNotificationKey.peerID.rawValue : peerID!] : nil)
        }
    }
    enum TransmissionProgressKey {
        /// Key for the NSMutableData object in the user info dictionary.
        case data
    }
    
    private let _local = LocalPeerManager()
    private let _remote = RemotePeerManager()
    
    
    /// stores acknowledged pinned peers
    private var pinnedPeers = SynchronizedSet<PeerID>()
    // maybe encrypt these on disk so no one can read out their display names
    private var pinnedByPeers = SynchronizedSet<PeerID>()
    
    let remote: RemotePeering
    let local: LocalPeering
    
    var availablePeers: [PeerID] {
        return _remote.availablePeripherals
    }
    
    var peering: Bool {
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
    
    func hasPinMatch(_ peerID: PeerID) -> Bool {
        return isPinned(peerID) && isPinned(by: peerID)
    }
    
    func isPinned(by peerID: PeerID) -> Bool {
        return pinnedByPeers.contains(peerID)
    }
    
    func pin(_ peerID: PeerID) {
        guard !isPinned(peerID) else { return }
        guard _local.availablePeers.contains(peerID) else { return }
        
        WalletController.requestPin { (confirmation) in
            NetworkNotification.pinningStarted.post(peerID)
            self._local.pin(peerID)
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
    
    func isPinned(_ peerID: PeerID) -> Bool {
        return pinnedPeers.contains(peerID)
    }
    
    func sessionHandlerDidPin(_ peerID: PeerID) {
        pinnedPeers.insert(peerID)
        pinnedPeers.accessQueue.async {
            // access the set on the queue to ensure the last peerID is also included ...
            // ... and besides get a smoother UI
            archiveObjectInUserDefs(self.pinnedPeers.set as NSSet, forKey: PeeringController.PinnedPeersKey)
        }
        if pinnedByPeers.contains(peerID) {
            pinMatchOccured(peerID)
        }
        
        NetworkNotification.pinned.post(peerID)
    }
    
    // MARK: RemotePeerManagerDelegate
    
//    func scanningStopped() {
//        if local.isAdvertising {
//            local.stopAdvertising()
//            connectionChangedState()
//        }
//    }
    
    func sessionHandlerReceivedPin(from peerID: PeerID) {
        pinnedByPeers.insert(peerID)
        pinnedByPeers.accessQueue.async {
            // access the set on the queue to ensure the last peerID is also included ...
            // ... and besides get a smoother UI
            archiveObjectInUserDefs(self.pinnedByPeers.set as NSSet, forKey: PeeringController.PinnedByPeersKey)
        }
        if pinnedPeers.contains(peerID) {
            pinMatchOccured(peerID)
        }
    }
    
    func peerAppeared(_ peerID: PeerID) {
        NetworkNotification.peerAppeared.post(peerID)
    }
    
    func peerDisappeared(_ peerID: PeerID) {
        NetworkNotification.peerDisappeared.post(peerID)
    }
    
    // MARK: Private Methods
    
    private init() {
        remote = _remote
        local = _local
        let nsPinnedBy: NSSet? = unarchiveObjectFromUserDefs(PeeringController.PinnedByPeersKey)
        pinnedByPeers = SynchronizedSet(set: nsPinnedBy as? Set<PeerID> ?? Set())
        let nsPinned: NSSet? = unarchiveObjectFromUserDefs(PeeringController.PinnedPeersKey)
        pinnedPeers = SynchronizedSet(set: nsPinned as? Set<PeerID> ?? Set())
        _remote.delegate = self
        _local.delegate = self
    }
    
    private func pinMatchOccured(_ peerID: PeerID) {
        NetworkNotification.pinMatch.post(peerID)
    }
    
    private func connectionChangedState() {
        NetworkNotification.connectionChangedState.post(nil)
    }
}
