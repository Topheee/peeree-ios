//
//  LocalPeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 21.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/**
 *	Coordinates the access to the MCPeerID of the local machine and caches it.
 *	This ID is preserved to enable other users to re-identify us more easily.
 */
public class LocalPeerManager {
	
	static private let kPrefPeerID = "peeree-prefs-peerID"
	static public let kDiscoveryServiceID = "peeree-discover"
	
	static private var localPeer: MCPeerID?
	
	/**
	 *	Unarchives the MCPeerID from NSUserDefaults, if it is already created.
	 *	@return the MCPeerID of the local machine.
	 */
	static public func getLocalPeer() -> MCPeerID? {
		if localPeer != nil {
			return localPeer
		}
		//load from preferences at first access
		let defs = NSUserDefaults.standardUserDefaults()
		if let peerData = defs.objectForKey(kPrefPeerID) as? NSData {
			localPeer = NSKeyedUnarchiver.unarchiveObjectWithData(peerData) as? MCPeerID
			return localPeer
		}
		return nil
	}
	
	/**
	 *	Creates a new MCPeerID using the given name, but only if the name is different from the former one.
	 *	@param name	the new name of the local device on the network.
	 */
	static public func setLocalPeerName(name: String) {
		if localPeer == nil || name != localPeer!.displayName {
			let tmpPeer = MCPeerID(displayName: name)
			//TODO exception-handling of MCPeerID constructor
			localPeer = tmpPeer
			let defs = NSUserDefaults.standardUserDefaults()
			defs.setObject(NSKeyedArchiver.archivedDataWithRootObject(tmpPeer), forKey: kPrefPeerID)
		}
	}
}