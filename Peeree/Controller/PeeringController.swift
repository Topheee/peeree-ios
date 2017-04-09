//
//  PeeringController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 04.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation

public protocol RemotePeering {
    var availablePeers: [PeerID] { get }
    var peersMet: Int { get }
    var isBluetoothOn: Bool { get }
    
    func getPeerInfo(of peerID: PeerID) -> PeerInfo?
//    func loadPeerInfo(of peerID: PeerID) -> Progress?
//    func isPeerInfoLoading(of peerID: PeerID) -> Progress?
    func loadPicture(of peer: PeerInfo) -> Progress?
    func isPictureLoading(of peerID: PeerID) -> Progress?
    func isPinning(_ peerID: PeerID) -> Bool
}

public enum PeerDistance {
    case unknown, close, nearby, far
}

//public protocol LocalPeering {
//}

/// The PeeringController singleton is the app's interface to the bluetooth network as well as to information about pinned peers.
public final class PeeringController : LocalPeerManagerDelegate, RemotePeerManagerDelegate {
    static private let PinnedPeersKey = "PinnedPeers"
    static private let PinnedByPeersKey = "PinnedByPeers"
    
    public static let shared = PeeringController()
    
    public enum NetworkNotificationKey: String {
        case peerID, again
    }
    
    public enum NetworkNotification: String {
        case connectionChangedState
        case peerAppeared, peerDisappeared
        case pinned, pinningStarted, pinFailed
        case pinMatch
        
        public func addObserver(usingBlock block: @escaping (Notification) -> Void) -> NSObjectProtocol {
            return NotificationCenter.addObserverOnMain(self.rawValue, usingBlock: block)
        }
        
        func post(_ peerID: PeerID?, again: Bool? = nil) {
            var userInfo: [AnyHashable: Any]? = nil
            if let id = peerID {
                if let a = again {
                    userInfo = [NetworkNotificationKey.peerID.rawValue : id, NetworkNotificationKey.again.rawValue : a]
                } else {
                    userInfo = [NetworkNotificationKey.peerID.rawValue : id]
                }
            }
            NotificationCenter.default.post(name: Notification.Name(rawValue: self.rawValue), object: PeeringController.shared, userInfo: userInfo)
        }
    }
    
    private let _local = LocalPeerManager()
    private let _remote = RemotePeerManager()
    
    /// stores acknowledged pinned peers
    private var pinnedPeers = SynchronizedSet<PeerID>()
    // maybe encrypt these on disk so no one can read out their display names
    private var pinnedByPeers = SynchronizedSet<PeerID>()
    
    private var pinningConfirmations = SynchronizedDictionary<PeerID, WalletController.PinConfirmation>()
    
    private var rangeBlock: ((PeerID, PeerDistance) -> Void)?
    
    public let remote: RemotePeering
//    public let local: LocalPeering
    
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
    
    @objc func callRange(_ timer: Timer) {
        PeeringController.shared._remote.range(timer.userInfo as! PeerID)
    }
    
    private func range(_ peerID: PeerID, timeInterval: TimeInterval, tolerance: TimeInterval, distance: PeerDistance) {
        guard rangeBlock != nil else { return }
        
        if #available(iOS 10.0, *) {
            let timer = Timer(timeInterval: timeInterval, repeats: false) { _ in
                PeeringController.shared._remote.range(peerID)
            }
            timer.tolerance = tolerance
            RunLoop.main.add(timer, forMode: .defaultRunLoopMode)
        } else {
            let timer = Timer(timeInterval: timeInterval, target: self, selector: #selector(PeeringController.callRange(_:)), userInfo: peerID, repeats: false)
            timer.tolerance = tolerance
            RunLoop.main.add(timer, forMode: .defaultRunLoopMode)
        }
        
        rangeBlock?(peerID, distance)
    }
    
    public func range(_ peerID: PeerID, block: @escaping (PeerID, PeerDistance) -> Void) {
        rangeBlock = block
        _remote.range(peerID)
    }
    
    public func stopRanging() {
        rangeBlock = nil
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
    
    func peerAppeared(_ peerID: PeerID, again: Bool) {
        NetworkNotification.peerAppeared.post(peerID, again: again)
    }
    
    func peerDisappeared(_ peerID: PeerID) {
        NetworkNotification.peerDisappeared.post(peerID)
    }
    
    func didPin(_ peerID: PeerID) {
        guard let confirmation = pinningConfirmations.removeValue(forKey: peerID) else {
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
        _ = pinningConfirmations.removeValue(forKey: peerID)
        NetworkNotification.pinFailed.post(peerID)
    }
    
    func isPinned(_ peerID: PeerID) -> Bool {
        return pinnedPeers.contains(peerID)
    }
    
    func didRange(_ peerID: PeerID, rssi: NSNumber?, error: Error?) {
        guard error == nil else {
            NSLog("Error updating range: \(error!.localizedDescription)") // TODO probably if the peripheral got out of range so we can delete this
            range(peerID, timeInterval: 7.0, tolerance: 2.5, distance: .unknown)
            return
        }
        switch rssi!.intValue {
        case -40 ... 100:
            range(peerID, timeInterval: 3.0, tolerance: 1.0, distance: .close)
        case -60 ... -40:
            range(peerID, timeInterval: 4.0, tolerance: 1.5, distance: .nearby)
        case -100 ... -60:
            range(peerID, timeInterval: 5.0, tolerance: 2.0, distance: .far)
        default:
            range(peerID, timeInterval: 7.0, tolerance: 2.5, distance: .unknown)
        }
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
