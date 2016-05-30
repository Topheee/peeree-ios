//
//  MCNearbyServiceBrowserMock.swift
//  Peeree
//
//  Created by Christopher Kobusch on 01.02.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import MultipeerConnectivity

class MCNearbyServiceBrowserMock: MCNearbyServiceBrowser {
	let peerEins = MCPeerID(displayName: "Peter Silie")
	let peerZwei = MCPeerID(displayName: "Rainer Wahnsinn")
	
	override func startBrowsingForPeers() {
		delegate?.browser(self, foundPeer: peerEins, withDiscoveryInfo: nil)
		delegate?.browser(self, foundPeer: peerZwei, withDiscoveryInfo: nil)
		NSTimer.scheduledTimerWithTimeInterval(5, target: self, selector: #selector(MCNearbyServiceBrowserMock.timerHier(_:)), userInfo: nil, repeats: false)
		NSTimer.scheduledTimerWithTimeInterval(2, target: self, selector: #selector(MCNearbyServiceBrowserMock.addPeer(_:)), userInfo: nil, repeats: true)
	}
	
	override func invitePeer(peerID: MCPeerID, toSession session: MCSession, withContext context: NSData?, timeout: NSTimeInterval) {
		let peerDescription = LocalPeerInfo()
		peerDescription.familyName = "Silie"
		peerDescription.givenName = "Peter"
		let data = NSKeyedArchiver.archivedDataWithRootObject(peerDescription)
		session.delegate?.session(session, didReceiveData: data, fromPeer: peerID)
	}
	
	func timerHier(userInfo: AnyObject?) {
		delegate?.browser(self, lostPeer: peerEins)
	}
	
	func addPeer(userInfo: AnyObject?) {
		delegate?.browser(self, foundPeer: MCPeerID(displayName: "Peer \(rand())"), withDiscoveryInfo: nil)
	}
}
