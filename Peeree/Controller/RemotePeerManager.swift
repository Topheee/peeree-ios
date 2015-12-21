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
	/* private */ var btBrowser: MCNearbyServiceBrowser?
	/*
	 *	All remote peers the app is currently connected to. This property is immediatly updated when a new connection is set up or an existing is cut off.
	 */
	var availablePeers = Set<MCPeerID>()
	var pinnedPeers: [LocalPeerInfo] = []
	
	var delegate: RemotePeerManagerDelegate?
	
	func goOnline() {
		let peerID = UserPeerInfo.instance.peerID

		if btAdvertiser == nil {
				// TODO maybe provide some information in discoveryInfo
				btAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: RemotePeerManager.kDiscoveryServiceID)
				btAdvertiser!.delegate = self
		}
		btAdvertiser?.startAdvertisingPeer()
		if btBrowser == nil {
				btBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: RemotePeerManager.kDiscoveryServiceID)
				btBrowser!.delegate = self
		}
		btBrowser?.startBrowsingForPeers()
	}
	
	func goOffline() {
		btAdvertiser?.stopAdvertisingPeer()
		btBrowser?.stopBrowsingForPeers()
		// TODO cancel and close all sessions. Seems, that we have to store them somewhere (maybe in the availablePeers tuple)
	}
	
	private func lostConnection(toPeer: MCPeerID) {
		availablePeers.remove(toPeer)
		delegate?.remotePeerDisappeared(toPeer)
	}
	
	private func newConnection(toPeer: MCPeerID) {
		if availablePeers.contains(toPeer) { return }
		availablePeers.insert(toPeer)
		
		delegate?.remotePeerAppeared(toPeer)
		
		if cachedPeers[toPeer] == nil {
			// immediatly begin to retrieve downloading information
			// TODO if this needs too much energy, disable this feature or make it optional. Note, that in this case filtering is not possible (except, we use the discovery info dict)
			beginPeerDescriptionDownloading(toPeer)
		}
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
	
	func filteredPeers(forFilterSettings: BrowseFilterSettings) -> [(String, String)] {
		var ret: [(String, String)] = []
		for elem in availablePeers.enumerate() {
			if let description = cachedPeers[elem.element] {
				let matchingGender = forFilterSettings.gender == .Unspecified || (forFilterSettings.gender == .Female && description.hasVagina)
				let matchingAge = forFilterSettings.ageMin <= Float(description.age) && (forFilterSettings.ageMax == 0.0 || forFilterSettings.ageMax >= Float(description.age))
				// TODO implement atLeastMyLanguage
				//let matchingLanguage = !forFilterSettings.atLeastMyLanguage
				
				if matchingAge && matchingGender {
					ret.append((elem.element.displayName, getPinStatus(elem.element)))
				}
			}
		}
		return ret
	}
	
	private func beginPeerDescriptionDownloading(forPeer: MCPeerID) {
		btBrowser?.invitePeer(forPeer, toSession: MCSession(peer: UserPeerInfo.instance.peerID, securityIdentity: nil, encryptionPreference: .Required), withContext: nil, timeout: RemotePeerManager.kInvitationTimeout)
	}
	
	@objc func advertiser(advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer: NSError) {
		// TODO implement this
	}
	
	@objc func advertiser(advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: NSData?, invitationHandler: (Bool, MCSession) -> Void) {
		// TODO The nearby peer should treat any data it receives as potentially untrusted. To learn more about working with untrusted data, read Secure Coding Guide.
		invitationHandler(true, MCSession(peer: UserPeerInfo.instance.peerID, securityIdentity: nil, encryptionPreference: MCEncryptionPreference.Required))
	}
	
	@objc func session(session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, atURL localURL: NSURL, withError error: NSError?) {
		// maybe use this, to display in the browser view controller, when we set up a new connection
	}
	
	@objc func session(session: MCSession, didReceiveCertificate certificate: [AnyObject]?, fromPeer peerID: MCPeerID, certificateHandler: (Bool) -> Void) {
		// TODO security implementation
	}
	
	@objc func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
		// TODO implement this
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
			break
		case .Connecting:
			break
		case .NotConnected:
			// TODO inform browse view controller
			break
		}
	}
	
	@objc func browser(browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: NSError) {
		// TODO error handling
	}
	
	@objc func browser(browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
		newConnection(peerID)
	}
	
	@objc func browser(browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		lostConnection(peerID)
	}
}

protocol RemotePeerManagerDelegate {
	func remotePeerAppeared(peer: MCPeerID)
	func remotePeerDisappeared(peer: MCPeerID)
}