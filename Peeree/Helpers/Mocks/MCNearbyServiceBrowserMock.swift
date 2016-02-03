//
//  MCNearbyServiceBrowserMock.swift
//  Peeree
//
//  Created by Christopher Kobusch on 01.02.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import MultipeerConnectivity

class MCNearbyServiceBrowserMock: MCNearbyServiceBrowser {
	let peerEins = MCPeerID(displayName: "Peer Eins")
	let peerZwei = MCPeerID(displayName: "Peer Zwei")
	
	override func startBrowsingForPeers() {
		delegate?.browser(self, foundPeer: peerEins, withDiscoveryInfo: nil)
		delegate?.browser(self, foundPeer: peerZwei, withDiscoveryInfo: nil)
		NSTimer.scheduledTimerWithTimeInterval(5, target: self, selector: Selector("timerHier:"), userInfo: nil, repeats: false)
		NSTimer.scheduledTimerWithTimeInterval(2, target: self, selector: Selector("addPeer:"), userInfo: nil, repeats: true)
	}
	
	override func invitePeer(peerID: MCPeerID, toSession session: MCSession, withContext context: NSData?, timeout: NSTimeInterval) {
		
	}
	
	func timerHier(userInfo: AnyObject?) {
		delegate?.browser(self, lostPeer: peerEins)
	}
	
	func addPeer(userInfo: AnyObject?) {
		delegate?.browser(self, foundPeer: MCPeerID(displayName: "Peer \(rand())"), withDiscoveryInfo: nil)
	}
}
