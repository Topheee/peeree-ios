//
//  PeerDescription.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import UIKit.UIImage

/**
 Class used only for unit testing.
 */
class TestPeerInfo: LocalPeerInfo {
    override init() {
        super.init()
        peerName = "Peter Silie"
    }
    
    @objc required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

protocol UserPeerInfoDelegate {
	func userConfirmedIDChange()
	func userCancelledIDChange()
	func idChangeDialogPresented()
}

class UserPeerInfo: LocalPeerInfo {
	private static let PrefKey = "UserPeerInfo"
	private static let DateOfBirthKey = "dateOfBirth"
	static var instance: UserPeerInfo {
        struct Singleton {
            static var sharedInstance: UserPeerInfo!
            static var token: dispatch_once_t = 0
        }
        dispatch_once(&Singleton.token, { () -> Void in
            Singleton.sharedInstance = unarchiveObjectFromUserDefs(PrefKey) ?? UserPeerInfo()
        })
        
        return Singleton.sharedInstance
	}
	
	var delegate: UserPeerInfoDelegate?
	
	var dateOfBirth: NSDate? {
		didSet {
			if dateOfBirth != oldValue {
				dirtied()
			}
		}
    }
    
    override var peerName: String {
        get { return super.peerName }
        set {
            guard peerName != "" && newValue != peerName else { return }
            
            warnIdentityChange({ (proceedAction) -> Void in
                super.peerName = newValue
                self.dirtied()
                self.delegate?.userConfirmedIDChange()
                }, cancelHandler: { (cancelAction) -> Void in
                    self.delegate?.userCancelledIDChange()
                }, completionHandler: { () -> Void in
                    self.delegate?.idChangeDialogPresented()
            })
        }
    }
//    override var givenName: String {
//        get { return super.givenName }
//        set {
//            if newValue != givenName {
//                warnIdentityChange({ (proceedAction) -> Void in
//                    super.givenName = newValue
//                    self.dirtied()
//                    self.delegate?.userConfirmedIDChange()
//                    }, cancelHandler: { (cancelAction) -> Void in
//                        self.delegate?.userCancelledIDChange()
//                    }, completionHandler: { () -> Void in
//                        self.delegate?.idChangeDialogPresented()
//                })
//            }
//        }
//    }
//	override var familyName: String {
//		get { return super.familyName }
//		set {
//			if newValue != familyName {
//				warnIdentityChange({ (proceedAction) -> Void in
//					super.familyName = newValue
//					self.dirtied()
//					self.delegate?.userConfirmedIDChange()
//					}, cancelHandler: { (cancelAction) -> Void in
//						self.delegate?.userCancelledIDChange()
//					}, completionHandler: { () -> Void in
//						self.delegate?.idChangeDialogPresented()
//				})
//			}
//		}
//	}
	override var age: Int {
        get {
            return super.age
        }
		set {
			fatalError("The age of the local user is defined by it's date of birth")
		}
	}
	override var hasVagina: Bool {
		didSet { if hasVagina != oldValue { dirtied() } }
	}
	override var statusID: Int {
		didSet { if statusID != oldValue { dirtied() } }
	}
    override var picture: UIImage? {
        get {
            return super.picture
        }
        set {
            _picture = newValue
            hasPicture = _picture != nil
        }
    }
	// TODO figure out what to do with characterTraits (maybe restrict the direct access and provide proxy methods) and version stuff
	
	private override init() {
		dateOfBirth = NSDate(timeIntervalSinceNow: -3600*24*365*18)
		super.init()
	}
//    init(name: String, birthday: NSDate?, picture: UIImage?) {
//        super.init(name: name, picture: picture)
//        peerName = name
//        dateOfBirth = birthday
//        archiveObjectInUserDefs(self, forKey: UserPeerInfo.PrefKey)
//    }

	@objc required init?(coder aDecoder: NSCoder) {
		dateOfBirth = aDecoder.decodeObjectOfClass(NSDate.self, forKey: UserPeerInfo.DateOfBirthKey) ?? NSDate(timeIntervalSinceNow: -3600*24*365*18)
	    super.init(coder: aDecoder)
	}
	
	private func warnIdentityChange(proceedHandler: ((UIAlertAction) -> Void)?, cancelHandler: ((UIAlertAction) -> Void)?, completionHandler: (() -> Void)?) {
		let ac = UIAlertController(title: NSLocalizedString("Change of Identity", comment: "Title message of alerting the user that he is about to change the unambigous representation of himself in the Peeree world."), message: NSLocalizedString("You are about to change your identification. If you continue, others, even the ones who pinned you, won't recognize you any more, even, if you reset your name to the previous one.", comment: "Description of 'Change of Identity'"), preferredStyle: .ActionSheet)
		ac.addAction(UIAlertAction(title: NSLocalizedString("Change", comment: "verb"), style: .Destructive, handler: proceedHandler))
		ac.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .Cancel, handler: cancelHandler))
		if let rootVC = UIApplication.sharedApplication().keyWindow?.rootViewController {
			let vc = rootVC.presentedViewController ?? rootVC
			vc.presentViewController(ac, animated: true, completion: completionHandler)
		}
	}
	
	private func dirtied() {
		archiveObjectInUserDefs(self, forKey: UserPeerInfo.PrefKey)
	}
}

/*
 *	This class is used to store remote peers locally. It provides an interface to load the picture of the remote peer lazily.
 */
class LocalPeerInfo: SerializablePeerInfo {
	private static let PictureKey = "picture"
	private static let PinnedKey = "pinnedMe"
	
	private var _picture: UIImage?
	var picture: UIImage? {
		return _picture
	}
	
	var _isPictureLoading = false
	var isPictureLoading: Bool {
		return _isPictureLoading
	}
	
	// is only set to true, if a pin match happend
	var pinnedMe = false
	
	func loadPicture() {
		if hasPicture && !_isPictureLoading {
			_isPictureLoading = true
			//TODO load picture
		}
	}
	
	@objc override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		if picture != nil {
			aCoder.encodeObject(picture, forKey: LocalPeerInfo.PictureKey)
		}
		aCoder.encodeBool(pinnedMe, forKey: LocalPeerInfo.PinnedKey)
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		if aDecoder.containsValueForKey(LocalPeerInfo.PictureKey) {
			_picture = aDecoder.decodeObjectOfClass(UIImage.self, forKey: LocalPeerInfo.PictureKey)
		}
		pinnedMe = aDecoder.decodeBoolForKey(LocalPeerInfo.PinnedKey)
	}

	private override init() {
	    super.init()
	}
}

/*
 *	This class encapsulates all data a peer has specified, except of his or her picture.
 *	It is transmitted to other peers when the peers connect, to allow filtering. In result, the primary goal is to keep the binary representation of this class as small as possible.
 */
class SerializablePeerInfo: NSObject, NSSecureCoding {
    private static let peerNameKey = "peerName"
	private static let peerIDKey = "peerID"
	private static let hasPictureKey = "hasPicture"
	private static let hasVaginaKey = "hasVagina"
	private static let ageKey = "age"
	private static let statusKey = "status"
	private static let traitsKey = "traits"
	private static let versionKey = "version"
    
    var peerName: String
    var displayName: String {
        get {
            var ret = peerName
            if peerName.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 63 {
                ret = peerName.substringToIndex(peerName.startIndex.advancedBy(60)) + "..."
            }
            if peerName.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) == 0 {
                //we need a value here for creating valid MCPeerIDs in the peerID getter
                ret = "Unknown"
            }
            return ret
        }
    }
	private var _peerID: MCPeerID?
	var peerID: MCPeerID {
		if _peerID == nil { _peerID = MCPeerID(displayName: displayName) }
		return _peerID!
	}
	var hasPicture = false
	var hasVagina = false
	var age = 18
	// TODO localization
	static let possibleStatuses = ["no comment", "married", "divorced", "going to be divorced", "in a relationship", "single"]
	var statusID = 0
	var characterTraits: [CharacterTrait]
	/*
	 *	Version information with the same format as Apple's dylib version format. This is used to test the compatibility of two Peeree apps exchanging data via bluetooth.
	 */
	var version = "1.0"
	
	private func resetPeerID() {
		_peerID = MCPeerID(displayName: displayName)
		// TODO maybe inform someone about this?
	}
	
	@objc static func supportsSecureCoding() -> Bool {
		return true
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeObject(peerName, forKey: SerializablePeerInfo.peerNameKey)
		aCoder.encodeObject(_peerID, forKey: SerializablePeerInfo.peerIDKey)
		aCoder.encodeBool(hasPicture, forKey: SerializablePeerInfo.hasPictureKey)
		aCoder.encodeBool(hasVagina, forKey: SerializablePeerInfo.hasVaginaKey)
		aCoder.encodeInteger(age, forKey: SerializablePeerInfo.ageKey)
		aCoder.encodeInteger(statusID, forKey: SerializablePeerInfo.statusKey)
		aCoder.encodeObject(version, forKey: SerializablePeerInfo.versionKey)
		aCoder.encodeObject(characterTraits, forKey: SerializablePeerInfo.traitsKey)
	}
	
	private override init() {
		characterTraits = CharacterTrait.standardTraits()
        peerName = ""
    }
    
	@objc required init?(coder aDecoder: NSCoder) {
		_peerID = aDecoder.decodeObjectOfClass(MCPeerID.self, forKey: SerializablePeerInfo.peerIDKey)
		hasPicture = aDecoder.decodeBoolForKey(SerializablePeerInfo.hasPictureKey)
		hasVagina = aDecoder.decodeBoolForKey(SerializablePeerInfo.hasVaginaKey)
		age = aDecoder.decodeIntegerForKey(SerializablePeerInfo.ageKey)
		statusID = aDecoder.decodeIntegerForKey(SerializablePeerInfo.statusKey)
		version = aDecoder.decodeObjectOfClass(NSString.self, forKey: SerializablePeerInfo.versionKey)! as String
		peerName = aDecoder.decodeObjectOfClass(NSString.self, forKey: SerializablePeerInfo.peerNameKey) as! String
		characterTraits = aDecoder.decodeObjectOfClass(NSArray.self, forKey: SerializablePeerInfo.traitsKey) as? [CharacterTrait] ?? CharacterTrait.standardTraits()
	}
}

func ==(lhs: SerializablePeerInfo, rhs: SerializablePeerInfo) -> Bool {
    return lhs._peerID == rhs.peerID
}