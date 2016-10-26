//
//  SessionHandlers.swift
//  Peeree
//
//  Created by Christopher Kobusch on 11.08.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import MultipeerConnectivity

class MCSessionDelegateAdapter: NSObject, MCSessionDelegate {
    static fileprivate let InvitationTimeout: TimeInterval = 5.0
    
    /// Only used to keep a reference to the session handlers so the RemotePeerManager does not have to.
    private var activeSessions: Set<MCSessionDelegateAdapter> = Set()
    
    let session = MCSession(peer: UserPeerInfo.instance.peer.peerID, securityIdentity: nil, encryptionPreference: .required)
    
    override init() {
        super.init()
        activeSessions.insert(self)
        session.delegate = self
    }
    
    func sendData(_ data: Data, toPeers peerIDs: [MCPeerID]) {
        do {
            try session.send(data, toPeers: peerIDs, with: .reliable)
        } catch let error as NSError where error.domain == MCErrorDomain {
            let errorCode = MCError(_nsError: error).code
            
            switch errorCode {
            case .unknown, .notConnected, .timedOut, .cancelled, .unavailable:
                // cancel gracefully here
                // error is known, peer is not connected, connection attempt timed out or cancelled by user or multipeer connectivity is currently unavailable.
                session.disconnect()
            case .invalidParameter, .unsupported:
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
    @objc func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    @objc func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL, withError error: Error?) {}
    @objc func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    @objc func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    
    @objc func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        // TODO security implementation
        certificateHandler(true)
    }
    
    @objc func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        if state == .notConnected {
            // this should be the last reference to self so it should destroy it
            session.delegate = nil
            activeSessions.remove(self)
        }
    }
}

/// Base class for all session handlers which retrieve information from an remote peers
class DownloadSessionDelegate: MCSessionDelegateAdapter {
    private static let MaxAttempts = 3
    
    fileprivate static var downloadSessions = SynchronizedDictionary<DownloadSessionID, DownloadSessionDelegate>()
    
    fileprivate struct DownloadSessionID: Hashable {
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
    fileprivate let sessionID: DownloadSessionID
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
        browser.invitePeer(sessionID.peerID, to: session, withContext: sessionID.sessionKey.rawData as Data, timeout: MCSessionDelegateAdapter.InvitationTimeout)
    }
    
    override func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected, .connecting:
            super.session(session, peer: peerID, didChange: state)
        case .notConnected:
            if willReconnect {
                connect()
            } else {
                super.session(session, peer: peerID, didChange: state)
                _ = DownloadSessionDelegate.downloadSessions.removeValueForKey(sessionID)
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
    
    override func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        super.session(session, peer: peerID, didChange: state)
        switch state {
        case .connected:
            let data = NSKeyedArchiver.archivedData(withRootObject: NetworkPeerInfo(peer: UserPeerInfo.instance.peer))
            sendData(data, toPeers: [peerID])
        case .connecting:
            break
        case .notConnected:
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
    override func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let info = NSKeyedUnarchiver.unarchiveObject(with: data) as? NetworkPeerInfo else { return }
        
        RemotePeerManager.sharedManager.sessionHandlerDidLoad(info)
        
        successful = true
    }
}

final class PictureDownloadSessionHandler: DownloadSessionDelegate {
    
    // KVO path strings for observing changes to properties of NSProgress
    static let ProgressCancelledKeyPath          = "cancelled"
    static let ProgressCompletedUnitCountKeyPath = "completedUnitCount"
    
    private var _progress: Progress? = nil
    var progress: Progress? { return _progress }
    
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
    
    override func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        _progress = progress
        progress.addObserver(self, forKeyPath: PictureDownloadSessionHandler.ProgressCancelledKeyPath, options: [.new], context: nil)
        progress.addObserver(self, forKeyPath: PictureDownloadSessionHandler.ProgressCompletedUnitCountKeyPath, options: [.new], context: nil)
    }
    
    // why the hell no override?!
    /* override */ func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL, withError error: NSError?) {
        // stop KVO
        progress?.removeObserver(self, forKeyPath:PictureDownloadSessionHandler.ProgressCancelledKeyPath)
        progress?.removeObserver(self, forKeyPath:PictureDownloadSessionHandler.ProgressCompletedUnitCountKeyPath)
        _progress = nil
        
        if let nsError = error {
            NSLog("Error receiving potrait picture: \(nsError)")
            delegate?.portraitLoadFailed(withError: nsError)
            
            successful = false
        } else {
            guard let data = try? Data(contentsOf: localURL) else { return }
            guard let image = UIImage(data: data) else { return }
            
            delegate?.portraitLoadFinished()
            RemotePeerManager.sharedManager.sessionHandlerDidLoad(image, ofPeer: peerID)
            
            successful = true
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
//        super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context) this throws an exception!
        guard let progress = object as? Progress else { return }
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
    func portraitLoadChanged(_ fractionCompleted: Double)
    func portraitLoadFinished()
    func portraitLoadFailed(withError error: NSError)
}

final class PictureUploadSessionManager: MCSessionDelegateAdapter {
    
    init(fromPeer peerID: MCPeerID, invitationHandler: (Bool, MCSession) -> Void) {
        super.init()
        invitationHandler(true, session)
    }
    
    override func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        super.session(session, peer: peerID, didChange: state)
        switch state {
        case .connected:
            session.sendResource(at: UserPeerInfo.instance.pictureResourceURL as URL, withName: "Bild", toPeer: peerID, withCompletionHandler: { (error) in
                guard let nsError = error else { return }
                
                NSLog("Error sending potrait picture: \(nsError)")
            })
        case .connecting:
            break
        case .notConnected:
            break
        }
    }
}

/// If the remote peer is unknown, it invited into the download session of the local peer.
final class PinSessionHandler: DownloadSessionDelegate {
    let confirmation: WalletController.PinConfirmation
    
    static func isPinning(_ peerID: MCPeerID) -> Bool {
        return DownloadSessionDelegate.downloadSessions[DownloadSessionID(peerID: peerID, sessionKey: .Pin)] != nil
    }
    
    init?(peerID: MCPeerID, btBrowser: MCNearbyServiceBrowser?, confirmation: WalletController.PinConfirmation) {
        self.confirmation = confirmation
        super.init(peerID: peerID, sessionKey: .Pin, failNotification: .PinFailed, btBrowser: btBrowser)
    }
    
    override func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            sendData(RemotePeerManager.SessionKey.Pin.rawData as Data, toPeers: [peerID])
        case .connecting:
            break
        case .notConnected:
            break
        }
        super.session(session, peer: peerID, didChange: state)
    }
    
    override func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard NSKeyedUnarchiver.unarchiveObject(with: data) as? String == "ack" else { return }
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
    
    override func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard RemotePeerManager.SessionKey(rawData: data) == RemotePeerManager.SessionKey.Pin else { return }
        
        let ackData = NSKeyedArchiver.archivedData(withRootObject: "ack")
        sendData(ackData, toPeers: [peerID])
        
        RemotePeerManager.sharedManager.sessionHandlerReceivedPin(from: peerID)
    }
}

private func ==(lhs: DownloadSessionDelegate.DownloadSessionID, rhs: DownloadSessionDelegate.DownloadSessionID) -> Bool {
    return lhs.hashValue == rhs.hashValue
}
