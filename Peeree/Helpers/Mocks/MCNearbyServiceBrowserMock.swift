//
//  MCNearbyServiceBrowserMock.swift
//  Peeree
//
//  Created by Christopher Kobusch on 01.02.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import MultipeerConnectivity

class MCNearbyServiceBrowserMock: MCNearbyServiceBrowser {
    private var addTimer: NSTimer?

    // all taken from RemotePeerManager:
    static private let DiscoveryServiceID = "peeree-discover"
    /// Identifies a MCSession as a session which transfers TestPeerInfo objects.
    static private let PeerInfoSessionKey = "PeerInfoSession"
    /// Session key for transmitting portrait images.
    static private let PictureSessionKey = "PictureSession"
    /// Session key for transmitting portrait images.
    static private let PinSessionKey = "PinSession"
	
	override func startBrowsingForPeers() {
        guard addTimer == nil else { return }
        let dummy = NSTimer()
        self.addPeer(dummy)
		addTimer = NSTimer.scheduledTimerWithTimeInterval(5, target: self, selector: #selector(MCNearbyServiceBrowserMock.addPeer(_:)), userInfo: nil, repeats: true)
	}
    
    override func stopBrowsingForPeers() {
        addTimer?.invalidate()
        addTimer = nil
    }
	
	override func invitePeer(peerID: MCPeerID, toSession session: MCSession, withContext context: NSData?, timeout: NSTimeInterval) {
        guard let contextString = String(data: context!, encoding: NSASCIIStringEncoding) else { return }
        
        assert(session.delegate != nil)
        
        let triggerTime = (Int64(NSEC_PER_SEC) * Int64(arc4random() % 3))
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, triggerTime), dispatch_get_main_queue(), { () -> Void in
            switch contextString {
            case MCNearbyServiceBrowserMock.PeerInfoSessionKey:
                let data = NSKeyedArchiver.archivedDataWithRootObject(TestPeerInfo(peerID: peerID))
                
                assert(session.delegate != nil)
                
                session.delegate?.session(session, peer: peerID, didChangeState: .Connected)
                session.delegate?.session(session, didReceiveData: data, fromPeer: peerID)
            case MCNearbyServiceBrowserMock.PictureSessionKey:
                let rand = arc4random()
                let image = UIImage(named: "Portrait_\(rand % 2)")!
                session.delegate?.session(session, peer: peerID, didChangeState: .Connected)
                let data = NSKeyedArchiver.archivedDataWithRootObject(image)
                session.delegate?.session(session, didReceiveData: data, fromPeer: peerID)
            case MCNearbyServiceBrowserMock.PinSessionKey:
                session.delegate?.session(session, peer: peerID, didChangeState: .Connected)
                let data = NSKeyedArchiver.archivedDataWithRootObject("no-ack")
                session.delegate?.session(session, didReceiveData: data, fromPeer: peerID)
            default:
                assertionFailure()
            }
        })
        //            let data = NSMutableData()
        //            let archiver = NSKeyedArchiver(forWritingWithMutableData: data)
        //            (peerDescription as NetworkPeerInfo).encodeWithCoder(archiver)
        //            archiver.finishEncoding()
        //            let data = NSKeyedArchiver.archivedDataWithRootObject(peerDescription as NetworkPeerInfo)
        //            let test = NSKeyedUnarchiver.unarchiveObjectWithData(data) //as? NetworkPeerInfo
	}
	
	func removePeer(timer: NSTimer) {
		delegate?.browser(self, lostPeer: timer.userInfo as! MCPeerID)
	}
	
	func addPeer(timer: NSTimer) {
        let peerID = MCPeerID(displayName: "Peer \(arc4random())")
        delegate?.browser(self, foundPeer: peerID, withDiscoveryInfo: nil)
        
        let rand = arc4random()
        if rand % 2 == 0 {
            NSTimer.scheduledTimerWithTimeInterval(5, target: self, selector: #selector(MCNearbyServiceBrowserMock.pinPeer(_:)), userInfo: nil, repeats: false)
        }
        
        NSTimer.scheduledTimerWithTimeInterval(NSTimeInterval(arc4random() % 30), target: self, selector: #selector(MCNearbyServiceBrowserMock.removePeer(_:)), userInfo: peerID, repeats: false)
    }
    
    func pinPeer(timer: NSTimer) {
        guard let peerID = timer.userInfo as? MCPeerID else { return }
        
        let adv = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: MCNearbyServiceBrowserMock.DiscoveryServiceID)
        let inv = {(invite: Bool, session: MCSession) -> Void in
            guard invite else { return }
            
            session.delegate?.session(session, peer: peerID, didChangeState: .Connected)
            let data = NSKeyedArchiver.archivedDataWithRootObject(MCNearbyServiceBrowserMock.PinSessionKey)
            session.delegate?.session(session, didReceiveData: data, fromPeer: peerID)
            // TODO receive ack and close
        }
        
        RemotePeerManager.sharedManager.advertiser(adv, didReceiveInvitationFromPeer: peerID, withContext: nil, invitationHandler: inv)
    }
}
