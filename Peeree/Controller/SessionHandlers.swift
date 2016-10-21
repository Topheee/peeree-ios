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
    
    let session = MCSession(peer: UserPeerInfo.instance.peer.peerID, securityIdentity: nil, encryptionPreference: .Required)
    
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
    
    private static var downloadSessions = SynchronizedDictionary<DownloadSessionID, DownloadSessionDelegate>()
    
    private struct DownloadSessionID: Hashable {
        let peerID: MCPeerID
        let sessionKey: RemotePeerManager.SessionKey
        
        var hashValue: Int
        
        init(peerID: MCPeerID, sessionKey: RemotePeerManager.SessionKey) {
            self.peerID = peerID
            self.sessionKey = sessionKey
            hashValue = peerID.hashValue + sessionKey.hashValue
        }
    }
    
    private let failNotification: RemotePeerManager.NetworkNotification
    private let sessionID: DownloadSessionID
    private weak var btBrowser: MCNearbyServiceBrowser?
    private var attempt = 0
    var successful = false {
        didSet {
            attempt = DownloadSessionDelegate.MaxAttempts
            session.disconnect()
        }
    }
    
    var willReconnect: Bool {
        return attempt < DownloadSessionDelegate.MaxAttempts && RemotePeerManager.sharedManager.peering && RemotePeerManager.sharedManager.availablePeers.contains(sessionID.peerID)
    }
    
    init(peerID: MCPeerID, sessionKey: RemotePeerManager.SessionKey, failNotification: RemotePeerManager.NetworkNotification, btBrowser: MCNearbyServiceBrowser?) {
        sessionID = DownloadSessionID(peerID: peerID, sessionKey: sessionKey)
        self.failNotification = failNotification
        self.btBrowser = btBrowser
        super.init()
        
        if DownloadSessionDelegate.downloadSessions[sessionID] == nil {
            DownloadSessionDelegate.downloadSessions[sessionID] = self
            connect()
        }
    }
    
    private func connect() {
        guard let browser = btBrowser else {
            session.disconnect()
            return
        }
        guard willReconnect else {
            session.disconnect()
            return
        }
        
        attempt += 1
        browser.invitePeer(sessionID.peerID, toSession: session, withContext: sessionID.sessionKey.rawData, timeout: MCSessionDelegateAdapter.InvitationTimeout)
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
                DownloadSessionDelegate.downloadSessions.removeValueForKey(sessionID)
                if !successful {
                    failNotification.post(sessionID.peerID)
                }
            }
        }
        
    }
}

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

final class PeerInfoDownloadSessionHandler: DownloadSessionDelegate {
    
    static func isPeerInfoLoading(ofPeerID peerID: MCPeerID) -> Bool {
        return DownloadSessionDelegate.downloadSessions[DownloadSessionID(peerID: peerID, sessionKey: .PeerInfo)] != nil
    }
    
    init?(peerID: MCPeerID, btBrowser: MCNearbyServiceBrowser?) {
        super.init(peerID: peerID, sessionKey: .PeerInfo, failNotification: .PeerInfoLoadFailed, btBrowser: btBrowser)
    }
    
    /// Stores new LocalPeerInfo data and ignores all other data. Stays in session until the LocalPeerInfo is received.
    override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
        guard let info = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? NetworkPeerInfo else { return }
        
        RemotePeerManager.sharedManager.sessionHandlerDidLoad(info)
        
        successful = true
    }
}

final class PictureDownloadSessionHandler: DownloadSessionDelegate {
    
    // KVO path strings for observing changes to properties of NSProgress
    static let ProgressCancelledKeyPath          = "cancelled"
    static let ProgressCompletedUnitCountKeyPath = "completedUnitCount"
    
    private var _progress: NSProgress? = nil
    var progress: NSProgress? { return _progress }
    
    weak var delegate: PotraitLoadingDelegate?
    
    static func getPictureLoadFraction(ofPeer peerID: MCPeerID) -> Double {
        return (DownloadSessionDelegate.downloadSessions[DownloadSessionID(peerID: peerID, sessionKey: .Picture)] as? PictureDownloadSessionHandler)?._progress?.fractionCompleted ?? 0.0
    }
    
    static func isPictureLoading(ofPeer peerID: MCPeerID) -> Bool {
        return DownloadSessionDelegate.downloadSessions[DownloadSessionID(peerID: peerID, sessionKey: .Picture)] != nil
    }
    
    static func setPictureLoadingDelegate(ofPeer peerID: MCPeerID, delegate: PotraitLoadingDelegate) {
        guard let picLoadSession = DownloadSessionDelegate.downloadSessions[DownloadSessionID(peerID: peerID, sessionKey: .Picture)] as? PictureDownloadSessionHandler else { return }
        
        picLoadSession.delegate = delegate
    }
    
    init?(peerID: MCPeerID, btBrowser: MCNearbyServiceBrowser?, delegate: PotraitLoadingDelegate?) {
        super.init(peerID: peerID, sessionKey: .Picture, failNotification: .PictureLoadFailed, btBrowser: btBrowser)
        self.delegate = delegate
    }
    
    override func session(session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, withProgress progress: NSProgress) {
        
        _progress = progress
        progress.addObserver(self, forKeyPath: PictureDownloadSessionHandler.ProgressCancelledKeyPath, options: [.New], context: nil)
        progress.addObserver(self, forKeyPath: PictureDownloadSessionHandler.ProgressCompletedUnitCountKeyPath, options: [.New], context: nil)
    }
    
    override func session(session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, atURL localURL: NSURL, withError error: NSError?) {
        // stop KVO
        progress?.removeObserver(self, forKeyPath:PictureDownloadSessionHandler.ProgressCancelledKeyPath)
        progress?.removeObserver(self, forKeyPath:PictureDownloadSessionHandler.ProgressCompletedUnitCountKeyPath)
        _progress = nil
        
        if let nsError = error {
            NSLog("Error receiving potrait picture: \(nsError)")
            delegate?.portraitLoadFailed(withError: nsError)
            
            successful = false
        } else {
            guard let data = NSData(contentsOfURL: localURL) else { return }
            guard let image = UIImage(data: data) else { return }
            
            delegate?.portraitLoadFinished()
            RemotePeerManager.sharedManager.sessionHandlerDidLoad(image, ofPeer: peerID)
            
            successful = true
        }
    }
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
//        super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context) this throws an exception!
        guard let progress = object as? NSProgress else { return }
        guard delegate != nil && keyPath != nil else { return }
        
        switch keyPath! {
        case PictureDownloadSessionHandler.ProgressCancelledKeyPath:
            delegate!.portraitLoadCancelled()
        case PictureDownloadSessionHandler.ProgressCompletedUnitCountKeyPath:
            delegate!.portraitLoadChanged(progress.fractionCompleted)
        default:
            break
        }
    }
}

protocol PotraitLoadingDelegate: class {
    func portraitLoadCancelled()
    func portraitLoadChanged(fractionCompleted: Double)
    func portraitLoadFinished()
    func portraitLoadFailed(withError error: NSError)
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
            session.sendResourceAtURL(UserPeerInfo.instance.pictureResourceURL, withName: "Bild", toPeer: peerID, withCompletionHandler: { (error) in
                guard let nsError = error else { return }
                
                NSLog("Error sending potrait picture: \(nsError)")
            })
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
    
    static func isPinning(peerID: MCPeerID) -> Bool {
        return DownloadSessionDelegate.downloadSessions[DownloadSessionID(peerID: peerID, sessionKey: .Pin)] != nil
    }
    
    init?(peerID: MCPeerID, btBrowser: MCNearbyServiceBrowser?, confirmation: WalletController.PinConfirmation) {
        self.confirmation = confirmation
        super.init(peerID: peerID, sessionKey: .Pin, failNotification: .PinFailed, btBrowser: btBrowser)
    }
    
    override func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
        switch state {
        case .Connected:
            sendData(RemotePeerManager.SessionKey.Pin.rawData, toPeers: [peerID])
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
            successful = false
            return
        }
        
        WalletController.redeem(confirmation)
        RemotePeerManager.sharedManager.sessionHandlerDidPin(peerID)
        successful = true
    }
}

final class PinnedSessionManager: MCSessionDelegateAdapter {
    
    init(fromPeer peerID: MCPeerID, invitationHandler: (Bool, MCSession) -> Void) {
        super.init()
        invitationHandler(true, session)
    }
    
    override func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
        guard RemotePeerManager.SessionKey(rawData: data) == RemotePeerManager.SessionKey.Pin else { return }
        
        let ackData = NSKeyedArchiver.archivedDataWithRootObject("ack")
        sendData(ackData, toPeers: [peerID])
        
        RemotePeerManager.sharedManager.sessionHandlerReceivedPin(from: peerID)
    }
}

private func ==(lhs: DownloadSessionDelegate.DownloadSessionID, rhs: DownloadSessionDelegate.DownloadSessionID) -> Bool {
    return lhs.hashValue == rhs.hashValue
}