//
//  RemotePeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.10.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import Foundation
import MultipeerConnectivity

// TODO make use of discoveryInfo, but update the information provided within it, when the user taps on a peer or at least when he wants to pin someone, since we cannot trust the information provided in discoveryInfo I think
/*
 *	The RemotePeerManager serves as an globally access point for information about all remote peers, whether they are currently in network range or were pinned in the past.
 */
class RemotePeerManager: NSObject, MCNearbyServiceAdvertiserDelegate, MCSessionDelegate, MCNearbyServiceBrowserDelegate {
	static let sharedManager = RemotePeerManager()
	static let kDiscoveryServiceID = "peeree-discover"
	static let kInvitationTimeout: NSTimeInterval = 5.0
	
	/*
	 *	Since bluetooth connections are not very reliable, all peers are cached for a reasonable amount of time (at least 30 Minutes).
	 */
	private var cachedPeers: [MCPeerID : LocalPeerInfo] = [:]
	/*
	 *	All the Bluetooth stuff.
	 *	Should be private, but then, we cannot mock them.
	 */
	/* private */ var btAdvertiser: MCNearbyServiceAdvertiser?
	/* private */ var btBrowser: MCNearbyServiceBrowserMock?
	/*
	 *	All remote peers the app is currently connected to. This property is immediatly updated when a new connection is set up or an existing is cut off.
	 */
	var availablePeers = Set<MCPeerID>()
	var pinnedPeers: [LocalPeerInfo] = []
	
	var delegate: RemotePeerManagerDelegate?
	
	func goOnline() {
		guard btAdvertiser == nil || btBrowser == nil else { return }
		
		let peerID = UserPeerInfo.instance.peerID
		
		// TODO maybe provide some information in discoveryInfo
		btAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: RemotePeerManager.kDiscoveryServiceID)
		btAdvertiser!.delegate = self
		
		btAdvertiser?.startAdvertisingPeer()
		
		btBrowser = MCNearbyServiceBrowserMock(peer: peerID, serviceType: RemotePeerManager.kDiscoveryServiceID)
		btBrowser!.delegate = self
		
		btBrowser?.startBrowsingForPeers()
	}
	
	func goOffline() {
		btAdvertiser?.stopAdvertisingPeer()
		btBrowser?.stopBrowsingForPeers()
		btAdvertiser = nil
		btBrowser = nil
		// TODO cancel and close all sessions. Seems, that we have to store them somewhere (maybe in the availablePeers tuple)
	}
	
	func getPinStatus(forPeer: MCPeerID) -> String {
		var contained = false
		var pinnedMe = false
		contained = pinnedPeers.contains { (lpd) -> Bool in
			if lpd.peerID == forPeer {
				pinnedMe = lpd.pinnedMe
				return true
			}
			return false
		}
		
		var displayString: String
		if contained {
			if pinnedMe {
				displayString = NSLocalizedString("Pin Match!", comment: "Two peers have pinned each other")
			} else {
				displayString = NSLocalizedString("Pinned.", comment: "The user marked someone as interesting")
			}
		} else {
			displayString = NSLocalizedString("Not yet pinned.", comment: "The user did not yet marked someone as interesting")
		}
		
		return displayString
	}
	
	func filteredPeers(forFilterSettings: BrowseFilterSettings) -> [(MCPeerID, String, String)] {
		var ret: [(MCPeerID, String, String)] = []
		for elem in availablePeers.enumerate() {
			if let description = cachedPeers[elem.element] {
				if forFilterSettings.checkPeer(description) {
					ret.append((elem.element, elem.element.displayName, getPinStatus(elem.element)))
				}
			} else {
				ret.append((elem.element, elem.element.displayName, getPinStatus(elem.element)))
			}
		}
		return ret
	}
	
	func getPeerInfo(forPeer peerID: MCPeerID, download: Bool = false) -> LocalPeerInfo? {
		if let ret = cachedPeers[peerID] {
			return ret
		} else if download {
            beginPeerDescriptionDownloading(peerID)
        }
		return nil
	}
	
	private func beginPeerDescriptionDownloading(forPeer: MCPeerID) {
		btBrowser?.invitePeer(forPeer, toSession: MCSession(peer: UserPeerInfo.instance.peerID, securityIdentity: nil, encryptionPreference: .Required), withContext: nil, timeout: RemotePeerManager.kInvitationTimeout)
	}
	
	// MARK: - MCNearbyServiceAdvertiserDelegate
	
	@objc func advertiser(advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer: NSError) {
		// TODO implement this
	}
	
	@objc func advertiser(advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: NSData?, invitationHandler: (Bool, MCSession) -> Void) {
		// TODO The nearby peer should treat any data it receives as potentially untrusted. To learn more about working with untrusted data, read Secure Coding Guide.
		let session = MCSession(peer: UserPeerInfo.instance.peerID, securityIdentity: nil, encryptionPreference: MCEncryptionPreference.Required)
		session.delegate = self
		invitationHandler(true, session)
	}
	
	// MARK: - MCSessionDelegate
	
	@objc func session(session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, atURL localURL: NSURL, withError error: NSError?) {
		// maybe use this, to display in the browser view controller, when we set up a new connection
	}
	
	@objc func session(session: MCSession, didReceiveCertificate certificate: [AnyObject]?, fromPeer peerID: MCPeerID, certificateHandler: (Bool) -> Void) {
		// TODO security implementation
	}
	
	@objc func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
		cachedPeers[peerID] = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? LocalPeerInfo
	}
	
	@objc func session(session: MCSession, didReceiveStream stream: NSInputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
		// I think, we do not need this
	}
	
	@objc func session(session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, withProgress progress: NSProgress) {
		// maybe use this, to display in the browser view controller, when we set up a new connection
	}
	
	@objc func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
		switch state {
		case .Connected:
			// TODO inform browse view controller, so that it can switch to the person detailed view
			// TODO test, whether the casts works as expected (thats, only encode the LocalPeerInfo subset)
			let data = NSKeyedArchiver.archivedDataWithRootObject(UserPeerInfo.instance as LocalPeerInfo)
            do {
                try session.sendData(data, toPeers: [peerID], withMode: MCSessionSendDataMode.Reliable)
            } catch let error as NSError {
                // TODO handle send fails
            }
			
			break
		case .Connecting:
			break
		case .NotConnected:
			// TODO inform browse view controller
			break
		}
	}
	
	// MARK: - MCNearbyServiceBrowserDelegate
	
	@objc func browser(browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: NSError) {
		// TODO error handling
	}
	
	@objc func browser(browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
		guard !availablePeers.contains(peerID) else { return }
		
		availablePeers.insert(peerID)
		
		let d = delegate ?? AppDelegate.sharedDelegate
		d.remotePeerAppeared(peerID)
		
		if cachedPeers[peerID] == nil {
			// immediatly begin to retrieve downloading information
			// TODO if this needs too much energy, disable this feature or make it optional. Note, that in this case filtering is not possible (except, we use the discovery info dict)
			beginPeerDescriptionDownloading(peerID)
		}
	}
	
	@objc func browser(browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		availablePeers.remove(peerID)
		let d = delegate ?? AppDelegate.sharedDelegate
		d.remotePeerDisappeared(peerID)
	}
}

protocol RemotePeerManagerDelegate {
	func remotePeerAppeared(peer: MCPeerID)
	func remotePeerDisappeared(peer: MCPeerID)
}