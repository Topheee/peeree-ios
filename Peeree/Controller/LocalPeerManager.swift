//
//  UserPeerManager.swift
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
class UserPeerManager {
	
	/* private class ObservedLocalPeerDescription: LocalPeerDescription {
		override var givenName: String {
			didSet {
				UserPeerManager.userPeerDescriptionChanged()
			}
		}
		override var familyName: String {
			didSet {
				UserPeerManager.userPeerDescriptionChanged()
			}
		}
		override var hasPicture: Bool {
			didSet {
				UserPeerManager.userPeerDescriptionChanged()
			}
		}
		override var hasVagina: Bool {
			didSet {
				UserPeerManager.userPeerDescriptionChanged()
			}
		}
		override var age: Int {
			didSet {
				UserPeerManager.userPeerDescriptionChanged()
			}
		}
		override var status: Int {
			didSet {
				UserPeerManager.userPeerDescriptionChanged()
			}
		}
		override var characterTraits: [CharacterTrait] {
			// TODO evaluate, whether this works, since the values in the array may change, but not the array itself, and so this event may not be triggered
			didSet {
				UserPeerManager.userPeerDescriptionChanged()
			}
		}
		override var version: String {
			didSet {
				UserPeerManager.userPeerDescriptionChanged()
			}
		}
		override var _picture: UIImage? {
			didSet {
				UserPeerManager.userPeerDescriptionChanged()
			}
		}
	} */
	
	static func updatePeerDescription() {
		if userPeerDescription != nil { archiveObjectInUserDefs(userPeerDescription!, forKey: kPrefPeerDesc) }
		// TODO maybe propagate this with an notification
	}
	
	static /* private */ let kPrefPeerID = "peeree-prefs-peerID"
	static private let kPrefPeerDesc = "peeree-prefs-peer-description"
	
	// TODO maybe set these to nil when a memory warning occurs
//	static private var userPeerID: MCPeerID?
	static private var userPeerDescription: LocalPeerDescription?
	
	/**
	 *	Unarchives the MCPeerID from NSUserDefaults, if it is already created.
	 *	@return the MCPeerID of the local machine.
	 */
//	static func getUserPeerID() -> MCPeerID? {
//		return userPeerID ?? unarchiveObjectFromUserDefs(kPrefPeerID)
//	}
	
	/**
	 *	Currently only used for test cases.
	 *	TODO Maybe expose this to the user, but first figure out the consequences!
	 */
//	static func dropUserPeerID() {
//		NSUserDefaults.standardUserDefaults().removeObjectForKey(kPrefPeerID)
//	}
	
	/**
	 *	Creates a new MCPeerID using the given name, but only if the name is different from the former one.
	 *	@param name	the new name of the local device on the network.
	 */
//	static func setUserPeerName(name: String) {
//		if userPeerID == nil || name != userPeerID!.displayName {
//			userPeerID = MCPeerID(displayName: name)
//			archiveObjectInUserDefs(userPeerID!, forKey: kPrefPeerID)
//			// TODO maybe propagate this with an notification or otherwise inform the RemotePeerManager, that it has to restart its services
//		}
//	}
	
	/**
	 *	Unarchives the MCPeerID from NSUserDefaults, if it is already created.
	 *	@return the MCPeerID of the local machine.
	 */
	static func getPeerDescription() -> LocalPeerDescription {
		if userPeerDescription == nil {
			userPeerDescription = unarchiveObjectFromUserDefs(kPrefPeerDesc) ?? LocalPeerDescription()
		}
		return userPeerDescription!
	}
	
	static func warnIdentityChange(proceedHandler: ((UIAlertAction) -> Void)?, cancelHandler: ((UIAlertAction) -> Void)?, completionHandler: (() -> Void)?) {
		let ac = UIAlertController(title: NSLocalizedString("Change of Identity", comment: "Title message of alerting the user that he is about to change the unambigous representation of himself in the Peeree world."), message: NSLocalizedString("You are about to change your identification. If you continue, others, even the ones who pinned you, won't recognize you any more, even, if you reset your name to the previous one.", comment: "Description of 'Change of Identity'"), preferredStyle: .ActionSheet)
		ac.addAction(UIAlertAction(title: NSLocalizedString("Change", comment: "verb"), style: .Destructive, handler: cancelHandler))
		ac.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .Cancel, handler: proceedHandler))
		UIApplication.sharedApplication().keyWindow?.rootViewController?.presentViewController(ac, animated: true, completion: completionHandler)
	}
}