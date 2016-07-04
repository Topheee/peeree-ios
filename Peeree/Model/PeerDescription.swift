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
    init(id: MCPeerID) {
        super.init()
        _peerID = id
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
	
	var dateOfBirth: NSDate {
		didSet {
			if dateOfBirth != oldValue {
                super.age = NSCalendar.currentCalendar().components(NSCalendarUnit.Year, fromDate: dateOfBirth, toDate: NSDate(), options: NSCalendarOptions.init(rawValue: 0)).year
				dirtied()
			}
		}
    }
    
    override var peerName: String {
        get { return super.peerName }
        set {
            guard newValue != "" && newValue != super.peerName else { return }
            
            if peerName == "Unknown" {
                super._peerID = MCPeerID(displayName: newValue)
            } else {
                warnIdentityChange({ (proceedAction) -> Void in
                    super._peerID = MCPeerID(displayName: newValue)
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
	// TODO figure out what to do with characterTraits (maybe restrict the direct access and provide proxy methods) and version stuff
	
	private override init() {
		dateOfBirth = NSDate(timeIntervalSinceNow: -3600*24*365*18)
		super.init()
	}

	@objc required init?(coder aDecoder: NSCoder) {
		dateOfBirth = aDecoder.decodeObjectOfClass(NSDate.self, forKey: UserPeerInfo.DateOfBirthKey) ?? NSDate(timeIntervalSinceNow: -3600*24*365*18)
	    super.init(coder: aDecoder)
    }
    
    @objc override func encodeWithCoder(aCoder: NSCoder) {
        super.encodeWithCoder(aCoder)
        aCoder.encodeObject(dateOfBirth, forKey: UserPeerInfo.DateOfBirthKey)
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

///	This class is used to store remote peers locally.
class LocalPeerInfo: SerializablePeerInfo {
    // TODO somehow update this on the local storage when one of the properties changes, either like in UserPeerInfo or directly in the RemotePeerManager
    
    /// The setter for the picture is provided here to enable lazy loading of the picture from the remote peer.
    override var picture: UIImage? {
        get {
            return super.picture
        }
        set {
            _picture = newValue
            _hasPicture = newValue != nil
        }
    }
    
    override var pinnedMe: Bool {
        get {
            return super.pinnedMe
        }
        set {
            _pinnedMe = newValue
        }
    }
    
    override var pinned: Bool {
        get {
            return super.pinned
        }
        set {
            _pinned = newValue
        }
    }
	
	@objc override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		if picture != nil {
			aCoder.encodeObject(picture, forKey: LocalPeerInfo.PictureKey)
        }
        aCoder.encodeBool(pinnedMe, forKey: LocalPeerInfo.PinnedMeKey)
        aCoder.encodeBool(pinned, forKey: LocalPeerInfo.PinnedKey)
	}

	private override init() {
	    super.init()
	}
    
    @objc required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

/// This class encapsulates all data a peer has specified, except of his or her picture. It is transmitted to other peers when the peers connect, to allow filtering. In result, the primary goal is to keep the binary representation of this class as small as possible.
class SerializablePeerInfo: NSObject, NSSecureCoding {
    private static let peerNameKey = "peerName"
	private static let peerIDKey = "peerID"
	private static let hasPictureKey = "hasPicture"
	private static let genderKey = "gender"
	private static let ageKey = "age"
	private static let statusKey = "status"
	private static let traitsKey = "traits"
    private static let versionKey = "version"
    private static let PictureKey = "picture"
    private static let PinnedMeKey = "pinnedMe"
    private static let PinnedKey = "pinned"
    private static let LastChangedKey = "lastChanged"
    
    static let MinAge = 13
    static let MaxAge = 100
    
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
    
    var peerName: String {
        return _peerID.displayName
    }
    
	private var _peerID: MCPeerID
	var peerID: MCPeerID {
		return _peerID
	}
    
	private var _hasPicture = false
    var hasPicture: Bool {
        return _hasPicture
     }
    
	var gender = Gender.Female
	var age = 18
    var relationshipStatus = RelationshipStatus.NoComment
    
	var characterTraits: [CharacterTrait]
	/*
	 *	Version information with the same format as Apple's dylib version format. This is used to test the compatibility of two Peeree apps exchanging data via bluetooth.
	 */
    var version = "1.0"
    
    var lastChanged = NSDate()
    
    /// Only stored in the LocalPeerInfo subclass. In this class it is not written to the encoder in encodeWithCoder.
    private var _picture: UIImage? = nil
    var picture: UIImage? {
        return _picture
    }
    
    /// Only stored in the LocalPeerInfo subclass. In this class it is not written to the encoder in encodeWithCoder.
    private var _pinnedMe = false
    private var _pinned = false
    var pinnedMe: Bool {
        return _pinnedMe
    }
    var pinned: Bool {
        return _pinnedMe
    }
    
    var pinStatus: String {
        if pinned {
            if pinnedMe {
                return NSLocalizedString("Pin Match!", comment: "Two peers have pinned each other")
            } else {
                return NSLocalizedString("Pinned.", comment: "The user marked someone as interesting")
            }
        } else {
            return NSLocalizedString("Not yet pinned.", comment: "The user did not yet marked someone as interesting")
        }
    }
	
	@objc static func supportsSecureCoding() -> Bool {
		return true
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(_peerID, forKey: SerializablePeerInfo.peerIDKey)
		aCoder.encodeBool(hasPicture, forKey: SerializablePeerInfo.hasPictureKey)
		aCoder.encodeObject(gender.rawValue, forKey: SerializablePeerInfo.genderKey)
		aCoder.encodeInteger(age, forKey: SerializablePeerInfo.ageKey)
		aCoder.encodeObject(relationshipStatus.rawValue, forKey: SerializablePeerInfo.statusKey)
        aCoder.encodeObject(version, forKey: SerializablePeerInfo.versionKey)
        aCoder.encodeObject(characterTraits, forKey: SerializablePeerInfo.traitsKey)
        aCoder.encodeObject(lastChanged, forKey: SerializablePeerInfo.LastChangedKey)
	}
	
	private override init() {
		characterTraits = CharacterTrait.standardTraits()
        _peerID = MCPeerID(displayName: "Unknown")
    }
    
	@objc required init?(coder aDecoder: NSCoder) {
        if let peerID = aDecoder.decodeObjectOfClass(MCPeerID.self, forKey: SerializablePeerInfo.peerIDKey) {
            _peerID = peerID
        } else {
            return nil
        }
        if let rawGenderValue = aDecoder.decodeObjectOfClass(NSString.self, forKey: SerializablePeerInfo.genderKey) as? String {
            if let optionalGender = Gender(rawValue:rawGenderValue) {
                gender = optionalGender
            } else {
                return nil
            }
        } else {
            return nil
        }
        if aDecoder.containsValueForKey(LocalPeerInfo.PinnedMeKey) {
            _pinnedMe = aDecoder.decodeBoolForKey(LocalPeerInfo.PinnedMeKey)
        } else {
            return nil
        }
        if let rawStatusValue = aDecoder.decodeObjectOfClass(NSString.self, forKey: SerializablePeerInfo.statusKey) as? String {
            relationshipStatus = RelationshipStatus(rawValue:rawStatusValue) ?? RelationshipStatus.NoComment
        } else {
            RelationshipStatus.NoComment
        }
        if let lastChangedValue = aDecoder.decodeObjectOfClass(NSDate.self, forKey: SerializablePeerInfo.LastChangedKey) {
            lastChanged = lastChangedValue
        }
        // TODO figure out whether version can stay optional here
        version = aDecoder.decodeObjectOfClass(NSString.self, forKey: SerializablePeerInfo.versionKey) as? String ?? "1.0"
        characterTraits = aDecoder.decodeObjectOfClass(NSArray.self, forKey: SerializablePeerInfo.traitsKey) as? [CharacterTrait] ?? CharacterTrait.standardTraits()
        _hasPicture = aDecoder.decodeBoolForKey(SerializablePeerInfo.hasPictureKey)
        _picture = aDecoder.decodeObjectOfClass(UIImage.self, forKey: LocalPeerInfo.PictureKey)
        age = aDecoder.decodeIntegerForKey(SerializablePeerInfo.ageKey)
        _pinned = aDecoder.decodeBoolForKey(LocalPeerInfo.PinnedKey)
	}
}

func ==(lhs: SerializablePeerInfo, rhs: SerializablePeerInfo) -> Bool {
    return lhs._peerID == rhs.peerID
}