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
        guard let sessionKey = RemotePeerManager.SessionKey(rawData: context!) else { assertionFailure(); return }
        
        assert(session.delegate != nil)
        
        let triggerTime = (Int64(NSEC_PER_SEC) * Int64(arc4random() % 3))
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, triggerTime), dispatch_get_main_queue(), { () -> Void in
            switch sessionKey {
            case .PeerInfo:
                let data = NSKeyedArchiver.archivedDataWithRootObject(TestPeerInfo(peerID: peerID))
                
                assert(session.delegate != nil)
                
                session.delegate?.session(session, peer: peerID, didChangeState: .Connected)
                session.delegate?.session(session, didReceiveData: data, fromPeer: peerID)
            case .Picture:
                let rand = arc4random()
                let progress = NSProgress(totalUnitCount: Int64(rand % 99999))
                session.delegate?.session(session, peer: peerID, didChangeState: .Connected)
                session.delegate?.session(session, didStartReceivingResourceWithName: "name", fromPeer: peerID, withProgress: progress)
                dispatch_async(dispatch_get_global_queue(0, 0), {
                    let url = NSBundle.mainBundle().URLForResource("IchAlbert", withExtension: ".jpg")!
                    for step in 0..<progress.totalUnitCount {
                        progress.completedUnitCount = step
                    }
                    let error: NSError? = (rand % 4 == 0) ? nil : NSError(domain: "test", code: 404, userInfo: nil)
                    session.delegate?.session(session, didFinishReceivingResourceWithName: "name", fromPeer: peerID, atURL: url, withError: error)
                })
            case .Pin:
                session.delegate?.session(session, peer: peerID, didChangeState: .Connected)
                let data = NSKeyedArchiver.archivedDataWithRootObject("ack")
                session.delegate?.session(session, didReceiveData: data, fromPeer: peerID)
            }
        })
	}
	
	func removePeer(timer: NSTimer) {
		delegate?.browser(self, lostPeer: timer.userInfo as! MCPeerID)
	}
	
	func addPeer(timer: NSTimer) {
        let peerID = MCPeerID(displayName: "Peer \(arc4random())")
        delegate?.browser(self, foundPeer: peerID, withDiscoveryInfo: nil)
        
        let rand = arc4random()
        if rand % 2 == 0 {
            NSTimer.scheduledTimerWithTimeInterval(2, target: self, selector: #selector(MCNearbyServiceBrowserMock.pinPeer(_:)), userInfo: peerID, repeats: false)
        }
        
        NSTimer.scheduledTimerWithTimeInterval(NSTimeInterval(arc4random() % 45), target: self, selector: #selector(MCNearbyServiceBrowserMock.removePeer(_:)), userInfo: peerID, repeats: false)
    }
    
    func pinPeer(timer: NSTimer) {
        guard let peerID = timer.userInfo as? MCPeerID else { return }
        
        let adv = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: MCNearbyServiceBrowserMock.DiscoveryServiceID)
        let inv = {(invite: Bool, session: MCSession) -> Void in
            guard invite else { return }
            
            session.delegate?.session(session, peer: peerID, didChangeState: .Connected)
            session.delegate?.session(session, didReceiveData: RemotePeerManager.SessionKey.Pin.rawData, fromPeer: peerID)
            // TODO receive ack and close
        }
        
        RemotePeerManager.sharedManager.advertiser(adv, didReceiveInvitationFromPeer: peerID, withContext: RemotePeerManager.SessionKey.Pin.rawData, invitationHandler: inv)
    }
}
