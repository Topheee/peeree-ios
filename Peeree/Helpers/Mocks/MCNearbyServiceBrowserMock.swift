//
//  MCNearbyServiceBrowserMock.swift
//  Peeree
//
//  Created by Christopher Kobusch on 01.02.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import MultipeerConnectivity

class MCNearbyServiceBrowserMock: MCNearbyServiceBrowser {
    private var addTimer: Timer?

    // all taken from RemotePeerManager:
    static private let DiscoveryServiceID = "peeree-discover"
	
	override func startBrowsingForPeers() {
        guard addTimer == nil else { return }
        let dummy = Timer()
        self.addPeer(dummy)
        self.addPeer(dummy)
        self.addPeer(dummy)
        self.addPeer(dummy)
		addTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(MCNearbyServiceBrowserMock.addPeer(_:)), userInfo: nil, repeats: true)
	}
    
    override func stopBrowsingForPeers() {
        addTimer?.invalidate()
        addTimer = nil
    }
	
	override func invitePeer(_ peerID: MCPeerID, to session: MCSession, withContext context: Data?, timeout: TimeInterval) {
        guard let sessionKey = RemotePeerManager.SessionKey(rawData: context!) else { assertionFailure(); return }
        
        assert(session.delegate != nil)
        
        let triggerTime = (Int64(NSEC_PER_SEC) * Int64(arc4random() % 3))
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(triggerTime) / Double(NSEC_PER_SEC), execute: { () -> Void in
            switch sessionKey {
            case .peerInfo:
                let data = NSKeyedArchiver.archivedData(withRootObject: TestPeerInfo(peerID: peerID))
                
                assert(session.delegate != nil)
                
                session.delegate?.session(session, peer: peerID, didChange: .connected)
                session.delegate?.session(session, didReceive: data, fromPeer: peerID)
            case .picture:
                let rand = arc4random()
                let progress = Progress(totalUnitCount: Int64(rand % 999))
                session.delegate?.session(session, peer: peerID, didChange: .connected)
                session.delegate?.session(session, didStartReceivingResourceWithName: "name", fromPeer: peerID, with: progress)
                DispatchQueue.global().async(execute: {
                    let url = Bundle.main.url(forResource: "IchAlbert", withExtension: ".jpg")!
                    for step in 0..<progress.totalUnitCount {
                        progress.completedUnitCount = step
                    }
                    let error: NSError? = (rand % 4 == 0) ? nil : NSError(domain: "test", code: 404, userInfo: nil)
                    session.delegate?.session(session, didFinishReceivingResourceWithName: "name", fromPeer: peerID, at: url, withError: error)
                })
            case .pin:
                session.delegate?.session(session, peer: peerID, didChange: .connected)
                let data = NSKeyedArchiver.archivedData(withRootObject: "ack")
                session.delegate?.session(session, didReceive: data, fromPeer: peerID)
            }
        })
	}
	
	func removePeer(_ timer: Timer) {
		delegate?.browser(self, lostPeer: timer.userInfo as! MCPeerID)
	}
	
	func addPeer(_ timer: Timer) {
        let peerID = MCPeerID(displayName: "Peer \(arc4random())")
        delegate?.browser(self, foundPeer: peerID, withDiscoveryInfo: nil)
        
        let rand = arc4random()
        if rand % 2 == 0 {
            Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(MCNearbyServiceBrowserMock.pinPeer(_:)), userInfo: peerID, repeats: false)
        }
        
        Timer.scheduledTimer(timeInterval: TimeInterval(arc4random() % 45), target: self, selector: #selector(MCNearbyServiceBrowserMock.removePeer(_:)), userInfo: peerID, repeats: false)
    }
    
    func pinPeer(_ timer: Timer) {
        guard let peerID = timer.userInfo as? MCPeerID else { return }
        
        let adv = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: MCNearbyServiceBrowserMock.DiscoveryServiceID)
        let inv = {(invite: Bool, session: MCSession?) -> Void in
            guard invite else { return }
            
            session?.delegate?.session(session!, peer: peerID, didChange: .connected)
            session?.delegate?.session(session!, didReceive: RemotePeerManager.SessionKey.pin.rawData as Data, fromPeer: peerID)
            // TODO receive ack and close
        }
        
        RemotePeerManager.shared.advertiser(adv, didReceiveInvitationFromPeer: peerID, withContext: RemotePeerManager.SessionKey.pin.rawData, invitationHandler: inv)
    }
}
