//
//  SessionHandlers.swift
//  Peeree
//
//  Created by Christopher Kobusch on 11.08.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import MultipeerConnectivity

class MCSessionDelegateAdapter: NSObject, MCSessionDelegate {
    static private let InvitationTimeout: NSTimeInterval = 5.0
    
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
class DownloadSessionDelegate: MCSessionDelegateAdapter {
    private static let MaxAttempts = 3
    private let failNotification: RemotePeerManager.NetworkNotification
    private let peerID: MCPeerID
    private let sessionKeyData: NSData
    private weak var btBrowser: MCNearbyServiceBrowser?
    private var attempt = 0
    
    var willReconnect: Bool {
        get {
            return attempt < DownloadSessionDelegate.MaxAttempts && RemotePeerManager.sharedManager.peering && RemotePeerManager.sharedManager.availablePeers.contains(peerID)
        }
        set {
            attempt = DownloadSessionDelegate.MaxAttempts
            session.disconnect()
        }
    }
    
    init(peerID: MCPeerID, sessionKey: RemotePeerManager.SessionKey, failNotification: RemotePeerManager.NetworkNotification, btBrowser: MCNearbyServiceBrowser?) {
        self.peerID = peerID
        self.failNotification = failNotification
        self.btBrowser = btBrowser
        sessionKeyData = sessionKey.rawValue.dataUsingEncoding(NSASCIIStringEncoding)!
        super.init()
    }
    
    private func connect() {
        guard let browser = btBrowser else {
            failNotification.post(peerID)
            return
        }
        guard willReconnect else {
            failNotification.post(peerID)
            return
        }
        
        attempt += 1
        browser.invitePeer(peerID, toSession: session, withContext: sessionKeyData, timeout: MCSessionDelegateAdapter.InvitationTimeout)
    }
    
    override func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
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
final class PeerInfoUploadSessionManager: MCSessionDelegateAdapter {
    
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
final class PeerInfoDownloadSessionHandler: DownloadSessionDelegate {
    
    init?(peerID: MCPeerID, btBrowser: MCNearbyServiceBrowser?) {
        super.init(peerID: peerID, sessionKey: .PeerInfo, failNotification: .PeerInfoLoadFailed, btBrowser: btBrowser)
    }
    
    /// Stores new LocalPeerInfo data and ignores all other data. Stays in session until the LocalPeerInfo is received.
    override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
        guard let info = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? NetworkPeerInfo else { return }
        
        RemotePeerManager.sharedManager.sessionHandlerDidLoad(info)
        
        willReconnect = false
    }
}

/// If the remote peer is unknown, it invited into the download session of the local peer.
final class PictureDownloadSessionHandler: DownloadSessionDelegate {
    
    private static var loadingPictures = SynchronizedSet<MCPeerID>()
    
    static func isPictureLoading(ofPeer: MCPeerID) -> Bool {
        return loadingPictures.contains(ofPeer)
    }
    
    init?(peerID: MCPeerID, btBrowser: MCNearbyServiceBrowser?) {
        super.init(peerID: peerID, sessionKey: .Picture, failNotification: .PictureLoadFailed, btBrowser: btBrowser)
    }
    
    override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
        guard let image = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? UIImage else { return }
        
        RemotePeerManager.sharedManager.sessionHandlerDidLoad(image, ofPeer: peerID)
        
        willReconnect = false
    }
    
    override func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
        if state == .NotConnected && !willReconnect {
            PictureDownloadSessionHandler.loadingPictures.remove(peerID)
        }
        super.session(session, peer: peerID, didChangeState: state)
    }
}

final class PictureUploadSessionManager: MCSessionDelegateAdapter {
    
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
final class PinSessionHandler: DownloadSessionDelegate {
    let confirmation: WalletController.PinConfirmation
    
    init?(peerID: MCPeerID, btBrowser: MCNearbyServiceBrowser?, confirmation: WalletController.PinConfirmation) {
        self.confirmation = confirmation
        super.init(peerID: peerID, sessionKey: .Pin, failNotification: .PinFailed, btBrowser: btBrowser)
    }
    
    override func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
        switch state {
        case .Connected:
            let data = NSKeyedArchiver.archivedDataWithRootObject(RemotePeerManager.SessionKey.Pin.rawValue)
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
        RemotePeerManager.sharedManager.sessionHandlerDidPin(peerID)
        willReconnect = false
    }
}

final class PinnedSessionManager: MCSessionDelegateAdapter {
    
    init(fromPeer peerID: MCPeerID, invitationHandler: (Bool, MCSession) -> Void) {
        super.init()
        invitationHandler(true, session)
    }
    
    override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
        guard NSKeyedUnarchiver.unarchiveObjectWithData(data) as? String == RemotePeerManager.SessionKey.Pin.rawValue else { return }
        
        let ackData = NSKeyedArchiver.archivedDataWithRootObject("ack")
        sendData(ackData, toPeers: [peerID])
        
        RemotePeerManager.sharedManager.sessionHandlerReceivedPin(from: peerID)
    }
}