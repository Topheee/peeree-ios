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
            guard newValue != "" && newValue != super.peerName else { return }
            
            if peerName == "" {
                super.peerName = newValue
            } else {
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
    }
	override var age: Int {
        get {
            return super.age
        }
		set {
			fatalError("The age of the local user is defined by it's date of birth")
		}
	}
	override var gender: Gender {
		didSet { if gender != oldValue { dirtied() } }
	}
	override var relationshipStatus: RelationshipStatus {
		didSet { if relationshipStatus != oldValue { dirtied() } }
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
	private static let genderKey = "gender"
	private static let ageKey = "age"
	private static let statusKey = "status"
	private static let traitsKey = "traits"
	private static let versionKey = "version"
    
    enum Gender: String {
        case Male, Female, Queer
        
        static let values = [Male, Female, Queer]

        // TODO write the value into strings file
        /*
         *  For genstrings
         *
         *  NSLocalizedString("Male", comment: "Male gender")
         *  NSLocalizedString("Female", comment: "Female gender")
         *  NSLocalizedString("Queer", comment: "Gender type for everyone who does not fit into the other two genders")
         */
    }
    
    enum RelationshipStatus: String {
        case NoComment, Single, Married, Divorced, SoonDivorced, InRelationship
        
        static let values = [NoComment, Single, Married, Divorced, SoonDivorced, InRelationship]
        
        // TODO write the value into strings file
        /*
         * For genstrings
         *
         *  NSLocalizedString("NoComment", comment: "The user does not want to expose his relationship status")
         *  NSLocalizedString("Single", comment: "The user is not in an relationship nor was married")
         *  NSLocalizedString("Married", comment: "The user is married")
         *  NSLocalizedString("Divorced", comment: "The user is divorced")
         *  NSLocalizedString("SoonDivorced", comment: "The user will be divorced")
         *  NSLocalizedString("InRelationship", comment: "The user is already in some kind of relationship")
         */
    }
    
    var peerName: String
    var displayName: String {
        get {
            var ret = peerName
            if peerName.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 63 {
                ret = peerName.substringToIndex(peerName.startIndex.advancedBy(60)) + "..."
            } else if peerName.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) == 0 {
                //we need a value here for always creating valid MCPeerIDs
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
	var gender = Gender.Female
	var age = 18
    var relationshipStatus = RelationshipStatus.NoComment
    
	var characterTraits: [CharacterTrait]
	/*
	 *	Version information with the same format as Apple's dylib version format. This is used to test the compatibility of two Peeree apps exchanging data via bluetooth.
	 */
	var version = "1.0"
	
	@objc static func supportsSecureCoding() -> Bool {
		return true
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeObject(peerName, forKey: SerializablePeerInfo.peerNameKey)
		aCoder.encodeObject(_peerID, forKey: SerializablePeerInfo.peerIDKey)
		aCoder.encodeBool(hasPicture, forKey: SerializablePeerInfo.hasPictureKey)
		aCoder.encodeObject(gender.rawValue, forKey: SerializablePeerInfo.genderKey)
		aCoder.encodeInteger(age, forKey: SerializablePeerInfo.ageKey)
		aCoder.encodeObject(relationshipStatus.rawValue, forKey: SerializablePeerInfo.statusKey)
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
        if let rawGenderValue = aDecoder.decodeObjectOfClass(NSString.self, forKey: SerializablePeerInfo.genderKey) as? String {
            gender = Gender(rawValue:rawGenderValue) ?? Gender.Female
        } else {
            assertionFailure()
        }
		age = aDecoder.decodeIntegerForKey(SerializablePeerInfo.ageKey)
        if let rawStatusValue = aDecoder.decodeObjectOfClass(NSString.self, forKey: SerializablePeerInfo.statusKey) as? String {
            relationshipStatus = RelationshipStatus(rawValue:rawStatusValue) ?? RelationshipStatus.NoComment
        } else {
            assertionFailure()
        }
		version = aDecoder.decodeObjectOfClass(NSString.self, forKey: SerializablePeerInfo.versionKey) as! String
		peerName = aDecoder.decodeObjectOfClass(NSString.self, forKey: SerializablePeerInfo.peerNameKey) as! String
		characterTraits = aDecoder.decodeObjectOfClass(NSArray.self, forKey: SerializablePeerInfo.traitsKey) as? [CharacterTrait] ?? CharacterTrait.standardTraits()
	}
}

func ==(lhs: SerializablePeerInfo, rhs: SerializablePeerInfo) -> Bool {
    return lhs._peerID == rhs.peerID
}