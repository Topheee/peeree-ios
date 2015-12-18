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
	
	private class ObservedLocalPeerDescription: LocalPeerDescription {
		override var firstname: String {
			didSet {
				LocalPeerManager.localPeerDescriptionChanged()
			}
		}
		override var lastname: String {
			didSet {
				LocalPeerManager.localPeerDescriptionChanged()
			}
		}
		override var peerID: MCPeerID {
			didSet {
				LocalPeerManager.localPeerDescriptionChanged()
			}
		}
		override var hasPicture: Bool {
			didSet {
				LocalPeerManager.localPeerDescriptionChanged()
			}
		}
		override var hasVagina: Bool {
			didSet {
				LocalPeerManager.localPeerDescriptionChanged()
			}
		}
		override var age: Int {
			didSet {
				LocalPeerManager.localPeerDescriptionChanged()
			}
		}
		override var status: Int {
			didSet {
				LocalPeerManager.localPeerDescriptionChanged()
			}
		}
		override var country: Int {
			didSet {
				LocalPeerManager.localPeerDescriptionChanged()
			}
		}
		override var languages: [Bool] {
			didSet {
				// TODO evaluate, whether this works, since the values in the array may change, but not the array itself, and so this event may not be triggered
				LocalPeerManager.localPeerDescriptionChanged()
			}
		}
		override var characterTraits: [CharacterTrait] {
			// TODO evaluate, whether this works, since the values in the array may change, but not the array itself, and so this event may not be triggered
			didSet {
				LocalPeerManager.localPeerDescriptionChanged()
			}
		}
		override var version: String {
			didSet {
				LocalPeerManager.localPeerDescriptionChanged()
			}
		}
		override var _picture: UIImage? {
			didSet {
				LocalPeerManager.localPeerDescriptionChanged()
			}
		}
	}
	
	static private func localPeerDescriptionChanged() {
		NSUserDefaults.standardUserDefaults().setObject(localPeerDescription!, forKey:kPrefPeerDesc)
		// TODO maybe propagate this with an notification
	}
	
	static /* private */ let kPrefPeerID = "peeree-prefs-peerID"
	static private let kPrefPeerDesc = "peeree-prefs-peer-description"
	
	// TODO maybe set these to nil when a memory warning occurs
	static private var localPeerID: MCPeerID?
	static private var localPeerDescription: ObservedLocalPeerDescription?
	
	/**
	 *	Unarchives the MCPeerID from NSUserDefaults, if it is already created.
	 *	@return the MCPeerID of the local machine.
	 */
	static public func getLocalPeerID() -> MCPeerID? {
		return localPeerID ?? NSUserDefaults.standardUserDefaults().objectForKey(kPrefPeerID) as? MCPeerID
	}
	
	/**
	 *	Currently only used for test cases.
	 *	TODO Maybe expose this to the user, but first figure out the consequences!
	 */
	static public func dropLocalPeerID() {
		NSUserDefaults.standardUserDefaults().removeObjectForKey(kPrefPeerID)
	}
	
	/**
	 *	Creates a new MCPeerID using the given name, but only if the name is different from the former one.
	 *	@param name	the new name of the local device on the network.
	 */
	static public func setLocalPeerName(name: String) {
		if localPeerID == nil || name != localPeerID!.displayName {
			localPeerID = MCPeerID(displayName: name)
			if let localPeerID = localPeerID {
				let defs = NSUserDefaults.standardUserDefaults()
				defs.setObject(localPeerID, forKey: kPrefPeerID)
				// TODO maybe propagate this with an notification or otherwise inform the RemotePeerManager, that it has to restart its services
			}
		}
	}
	
	/**
	 *	Unarchives the MCPeerID from NSUserDefaults, if it is already created.
	 *	@return the MCPeerID of the local machine.
	 */
	static func getLocalPeerDescription() -> LocalPeerDescription {
		return localPeerDescription ?? NSUserDefaults.standardUserDefaults().objectForKey(kPrefPeerDesc) as? ObservedLocalPeerDescription ?? ObservedLocalPeerDescription()
	}
}