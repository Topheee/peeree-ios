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
    func indicatePinMatch(to peer: PeerInfo)
    func verify(_ peerID: PeerID)
}

public enum PeerDistance {
    case unknown, close, nearby, far
}

//public protocol LocalPeering {
//}

/// The PeeringController singleton is the app's interface to the bluetooth network as well as to information about pinned peers.
public final class PeeringController : LocalPeerManagerDelegate, RemotePeerManagerDelegate {
    public static let shared = PeeringController()
    
    public enum NetworkNotificationKey: String {
        case peerID, again
    }
    
    public enum Notifications: String {
        case connectionChangedState
        case peerAppeared, peerDisappeared
        case verified, verificationFailed
        case pictureLoaded
        
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
    
    private var rangeBlock: ((PeerID, PeerDistance) -> Void)?
    
    public let remote: RemotePeering
//    public let local: LocalPeering
    
    public var peering: Bool {
        get {
            return _local.isAdvertising //|| _remote.isScanning
        }
        set {
            if newValue {
                guard AccountController.shared.accountExists else { return }
                
                _local.startAdvertising()
                _remote.scan()
            } else {
                _local.stopAdvertising()
                _remote.stopScan()
            }
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
    
    func receivedPinMatchIndication(from peerID: PeerID) {
       AccountController.shared.updatePinStatus(of: peerID)
    }
    
    // MARK: RemotePeerManagerDelegate
    
//    func scanningStopped() {
//        if local.isAdvertising {
//            local.stopAdvertising()
//            connectionChangedState()
//        }
//    }
    
    func peerAppeared(_ peerID: PeerID, again: Bool) {
        Notifications.peerAppeared.post(peerID, again: again)
    }
    
    func peerDisappeared(_ peerID: PeerID) {
        Notifications.peerDisappeared.post(peerID)
    }
    
    func pictureLoaded(of peerID: PeerID) {
        Notifications.pictureLoaded.post(peerID)
    }
    
    func shouldIndicatePinMatch(to peer: PeerInfo) -> Bool {
        return AccountController.shared.hasPinMatch(peer)
    }
    
    func didRange(_ peerID: PeerID, rssi: NSNumber?, error: Error?) {
        guard error == nil else {
            NSLog("Error updating range: \(error!.localizedDescription)")
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
    
    func failedVerification(of peerID: PeerID, error: Error) {
        Notifications.verificationFailed.post(peerID)
    }
    
    func didVerify(_ peerID: PeerID) {
        Notifications.verified.post(peerID)
    }
    
    // MARK: Private Methods
    
    private init() {
        remote = _remote
//        local = _local
        _remote.delegate = self
        _local.delegate = self
    }
    
    private func connectionChangedState() {
        Notifications.connectionChangedState.post(nil)
    }
}
