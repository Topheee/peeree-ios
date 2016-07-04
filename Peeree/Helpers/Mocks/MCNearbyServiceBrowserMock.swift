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

    // both taken from RemotePeerManager:
    /// Identifies a MCSession as a session which transfers TestPeerInfo objects.
    static private let kPeerInfoSessionKey = "PeerInfoSession"
    /// Session key for transmitting portrait images.
    static private let kPictureSessionKey = "PictureSession"
	
	override func startBrowsingForPeers() {
        guard addTimer == nil else { return }
		addTimer = NSTimer.scheduledTimerWithTimeInterval(5, target: self, selector: #selector(MCNearbyServiceBrowserMock.addPeer(_:)), userInfo: nil, repeats: true)
	}
    
    override func stopBrowsingForPeers() {
        addTimer?.invalidate()
        addTimer = nil
    }
	
	override func invitePeer(peerID: MCPeerID, toSession session: MCSession, withContext context: NSData?, timeout: NSTimeInterval) {
        guard let contextString = String(data: context!, encoding: NSASCIIStringEncoding) else { return }
        
        switch contextString {
        case MCNearbyServiceBrowserMock.kPeerInfoSessionKey:
            let rand = arc4random()
            let peerDescription = TestPeerInfo(id: peerID)
            peerDescription.age = SerializablePeerInfo.MinAge + (Int(rand) % (SerializablePeerInfo.MaxAge - SerializablePeerInfo.MinAge))
            peerDescription.pinned = rand % 2 == 0
            peerDescription.pinnedMe = (rand % 1000) > 500
            peerDescription.picture = UIImage(named: "Portrait_\(rand % 3)")
            
            session.delegate?.session(session, peer: peerID, didChangeState: .Connected)
            let data = NSMutableData()
            let archiver = NSKeyedArchiver(forWritingWithMutableData: data)
            (peerDescription as SerializablePeerInfo).encodeWithCoder(archiver)
            let test = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? TestPeerInfo
            session.delegate?.session(session, didReceiveData: data, fromPeer: peerID)
            
            NSTimer.scheduledTimerWithTimeInterval(NSTimeInterval(arc4random() % 60), target: self, selector: #selector(MCNearbyServiceBrowserMock.removePeer(_:)), userInfo: peerID, repeats: false)
        case MCNearbyServiceBrowserMock.kPictureSessionKey:
            let picture = UIImage(named: "Sample Profile Pic")!
            session.delegate?.session(session, peer: peerID, didChangeState: .Connected)
            let data = NSKeyedArchiver.archivedDataWithRootObject(picture)
            session.delegate?.session(session, didReceiveData: data, fromPeer: peerID)
        default:
            assertionFailure()
        }
	}
	
	func removePeer(timer: NSTimer) {
		delegate?.browser(self, lostPeer: timer.userInfo as! MCPeerID)
	}
	
	func addPeer(timer: NSTimer) {
		delegate?.browser(self, foundPeer: MCPeerID(displayName: "Peer \(arc4random())"), withDiscoveryInfo: nil)
	}
}
