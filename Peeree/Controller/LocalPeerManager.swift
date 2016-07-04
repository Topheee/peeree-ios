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
final class UserPeerManager {
	
	static func updatePeerDescription() {
		if userPeerDescription != nil { archiveObjectInUserDefs(userPeerDescription!, forKey: kPrefPeerDesc) }
		// TODO maybe propagate this with an notification
	}
	
	static /* private */ let kPrefPeerID = "peeree-prefs-peerID"
	static private let kPrefPeerDesc = "peeree-prefs-peer-description"
    
    /**
     *	Unarchives the MCPeerID from NSUserDefaults, if it is already created.
     *	@return the MCPeerID of the local machine.
     */
    static var userPeerDescription: LocalPeerDescription {
        struct Singleton {
            static var sharedInstance: LocalPeerDescription!
            static var token: dispatch_once_t = 0
        }
        dispatch_once(&Singleton.token, { () -> Void in
            Singleton.sharedInstance = unarchiveObjectFromUserDefs(kPrefPeerDesc) ?? LocalPeerDescription()
        })
        
        return Singleton.sharedInstance
    }
	
	static func warnIdentityChange(proceedHandler: ((UIAlertAction) -> Void)?, cancelHandler: ((UIAlertAction) -> Void)?, completionHandler: (() -> Void)?) {
		let ac = UIAlertController(title: NSLocalizedString("Change of Identity", comment: "Title message of alerting the user that he is about to change the unambigous representation of himself in the Peeree world."), message: NSLocalizedString("You are about to change your identification. If you continue, others, even the ones who pinned you, won't recognize you any more, even, if you reset your name to the previous one.", comment: "Description of 'Change of Identity'"), preferredStyle: .ActionSheet)
		ac.addAction(UIAlertAction(title: NSLocalizedString("Change", comment: "verb"), style: .Destructive, handler: cancelHandler))
		ac.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .Cancel, handler: proceedHandler))
		UIApplication.sharedApplication().keyWindow?.rootViewController?.presentViewController(ac, animated: true, completion: completionHandler)
	}
}