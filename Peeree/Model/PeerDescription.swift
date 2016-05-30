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

protocol UserPeerInfoDelegate {
	func userConfirmedIDChange()
	func userCancelledIDChange()
	func idChangeDialogPresented()
}

class UserPeerInfo: LocalPeerInfo {
	private static let PrefKey = "UserPeerInfo"
	private static let DateOfBirthKey = "dateOfBirth"
	private static var _instance: UserPeerInfo?
	static var instance: UserPeerInfo {
		if _instance == nil {
			_instance = unarchiveObjectFromUserDefs(PrefKey) ?? UserPeerInfo()
		}
		return _instance!
	}
	
	var delegate: UserPeerInfoDelegate?
	
	var dateOfBirth: NSDate {
		didSet {
			if dateOfBirth != oldValue {
				age = -Int(dateOfBirth.timeIntervalSinceNow / (3600*24*365))
				dirtied()
			}
		}
	}
	
	override var givenName: String {
		get { return super.givenName }
		set {
			if newValue != givenName {
				warnIdentityChange({ (proceedAction) -> Void in
					super.givenName = newValue
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
	override var familyName: String {
		get { return super.familyName }
		set {
			if newValue != familyName {
				warnIdentityChange({ (proceedAction) -> Void in
					super.familyName = newValue
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
        }
    }
	// TODO figure out what to do with characterTraits (maybe restrict the direct access and provide proxy methods) and version stuff
	
	required init() {
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
	
	var _picture: UIImage?
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

	@objc required init() {
	    super.init()
	}
}

/*
 *	This class encapsulates all data a peer has specified, except of his or her picture.
 *	It is transmitted to other peers when the peers connect, to allow filtering. In result, the primary goal is to keep the binary representation of this class as small as possible.
 */
class SerializablePeerInfo: NSObject, NSSecureCoding {
	private static let personNameKey = "personName"
	private static let peerIDKey = "peerID"
	private static let hasPictureKey = "hasPicture"
	private static let hasVaginaKey = "hasVagina"
	private static let ageKey = "age"
	private static let statusKey = "status"
	private static let traitsKey = "traits"
	private static let versionKey = "version"
	
	/* We have to restrict the access to the name components, since changing these will also change our peer ID, which is necessary to be confirmed by the user.
	 * Also, be aware of giving the user the possibility to enter a nickname. Because these can change more likely than the given and family name, it must either be secured, that the nickname does never occur in the displayName (but this is rather difficult, because the behaviour of NSPersonNameComponentsFormatter cannot completely controlled by the developer), or the user has to always drop his Peeree identity, when his nickname changes.
	 */
	private let personName: NSPersonNameComponents
	var givenName: String {
		get {
			return personName.givenName ?? ""
		}
		set {
			if newValue != givenName {
				self.personName.givenName = newValue
				self.resetPeerID()
			}
		}
	}
	var familyName: String {
		get {
			return personName.familyName ?? ""
		}
		set {
			if newValue != familyName {
				self.personName.familyName = newValue
				self.resetPeerID()
			}
		}
	}
	var displayName: String {
		get {
			// TODO localization with NSPersonNameFormatter
			let formatter = NSPersonNameComponentsFormatter()
			let styles: [NSPersonNameComponentsFormatterStyle] = [.Long, .Medium, .Short, .Abbreviated]
			var ret: String
			var i = 0
			repeat {
				formatter.style = styles[i]
				ret = formatter.stringFromPersonNameComponents(personName)
                i = i+1
			} while ret.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 63 && i < styles.count
			if i == styles.count {
				// TODO substring of 60 bytes length plus "..." string
				//ret = ret.substringToIndex(64) + "..."
			}
            if ret.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) == 0 {
                //we need a value here for creating valid MCPeerIDs in the peerID getter
                ret = "Unknown"
            }
			return ret
		}
	}
    var fullName: String {
        let formatter = NSPersonNameComponentsFormatter()
        formatter.style = .Long
        return formatter.stringFromPersonNameComponents(personName)
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
		aCoder.encodeObject(personName, forKey: SerializablePeerInfo.personNameKey)
		aCoder.encodeObject(_peerID, forKey: SerializablePeerInfo.peerIDKey)
		aCoder.encodeBool(hasPicture, forKey: SerializablePeerInfo.hasPictureKey)
		aCoder.encodeBool(hasVagina, forKey: SerializablePeerInfo.hasVaginaKey)
		aCoder.encodeInteger(age, forKey: SerializablePeerInfo.ageKey)
		aCoder.encodeInteger(statusID, forKey: SerializablePeerInfo.statusKey)
		aCoder.encodeObject(version, forKey: SerializablePeerInfo.versionKey)
		aCoder.encodeObject(characterTraits, forKey: SerializablePeerInfo.traitsKey)
	}
	
	@objc required override init() {
		// TODO empty stub
		personName = NSPersonNameComponents()
		characterTraits = CharacterTrait.standardTraits()
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		personName = aDecoder.decodeObjectOfClass(NSPersonNameComponents.self, forKey: SerializablePeerInfo.personNameKey) ?? NSPersonNameComponents()
		_peerID = aDecoder.decodeObjectOfClass(MCPeerID.self, forKey: SerializablePeerInfo.peerIDKey)
		hasPicture = aDecoder.decodeBoolForKey(SerializablePeerInfo.hasPictureKey)
		hasVagina = aDecoder.decodeBoolForKey(SerializablePeerInfo.hasVaginaKey)
		age = aDecoder.decodeIntegerForKey(SerializablePeerInfo.ageKey)
		statusID = aDecoder.decodeIntegerForKey(SerializablePeerInfo.statusKey)
		version = aDecoder.decodeObjectOfClass(NSString.self, forKey: SerializablePeerInfo.versionKey)! as String
//		lastname = aDecoder.decodeObjectOfClass(NSString.self, forKey: NetworkPeerDescription.lastnameKey) as! String
		characterTraits = aDecoder.decodeObjectOfClass(NSArray.self, forKey: SerializablePeerInfo.traitsKey) as? [CharacterTrait] ?? CharacterTrait.standardTraits()
	}
}

/* This structure is used locally within the application. It simplifies handling with peer information, since we can easily provide immutable sets of data and can realize data integrity checks elsewhere.
*/
/* struct PeerInfo {
let personName: NSPersonNameComponents
var givenName: String { return personName.givenName ?? "" }
var familyName: String { return personName.familyName ?? "" }
var displayName: String {
let formatter = NSPersonNameComponentsFormatter()
formatter.style = .Long
let styles: [NSPersonNameComponentsFormatterStyle] = [.Long, .Medium, .Short, .Abbreviated]
var ret: String
var i = 0
repeat {
formatter.style = styles[i]
ret = formatter.stringFromPersonNameComponents(personName)
} while ret.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 63 && ++i < styles.count
if i == styles.count {
// TODO substring of 60 bytes length plus "..." string
//ret = ret.substringToIndex(64) + "..."
}
return ret
}
var peerID: MCPeerID
var hasPicture: Bool
var hasVagina: Bool
var age: Int
var statusID: Int
var characterTraits: [CharacterTrait]
var version: String
} */

/* class SerializablePeerInfo: NSObject, NSSecureCoding {
	private static let personNameKey = "personName"
	private static let peerIDKey = "peerID"
	private static let hasPictureKey = "hasPicture"
	private static let hasVaginaKey = "hasVagina"
	private static let ageKey = "age"
	private static let statusKey = "status"
	private static let traitsKey = "traits"
	private static let versionKey = "version"
	
	private var _info: PeerInfo
	var peerInfo: PeerInfo {
		return _info
	}
	
	var personName: NSPersonNameComponents { return _info.personName }
	var givenName: String { return _info.givenName }
	var familyName: String { return _info.familyName }
	var displayName: String { return _info.displayName }
	var peerID: MCPeerID { return _info.peerID }
	var hasPicture: Bool { return _info.hasPicture }
	var hasVagina: Bool { return _info.hasVagina }
	var age: Int { return _info.age }
	var statusID: Int { return _info.statusID }
	var characterTraits: [CharacterTrait] { return _info.characterTraits }
	var version: String { return _info.version }
	
	static func supportsSecureCoding() -> Bool {
		return true
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		let personName: NSPersonNameComponents = aDecoder.decodeObjectOfClass(NSPersonNameComponents.self, forKey: SerializablePeerInfo.personNameKey)!
		let peerID: MCPeerID = aDecoder.decodeObjectOfClass(MCPeerID.self, forKey: SerializablePeerInfo.peerIDKey)!
		let hasPicture: Bool = aDecoder.decodeBoolForKey(SerializablePeerInfo.hasPictureKey)
		let hasVagina: Bool = aDecoder.decodeBoolForKey(SerializablePeerInfo.hasVaginaKey)
		let age: Int = aDecoder.decodeIntegerForKey(SerializablePeerInfo.ageKey)
		let statusID: Int = aDecoder.decodeIntegerForKey(SerializablePeerInfo.statusKey)
		let characterTraits: [CharacterTrait] = aDecoder.decodeObjectOfClass(NSArray.self, forKey: SerializablePeerInfo.traitsKey)! as! [CharacterTrait]
		let version: String = aDecoder.decodeObjectOfClass(NSString.self, forKey: SerializablePeerInfo.versionKey)! as String
		_info = PeerInfo(personName: personName, peerID: peerID, hasPicture: hasPicture, hasVagina: hasVagina, age: age, statusID: statusID, characterTraits: characterTraits, version: version)
	}
	
	func encodeWithCoder(aCoder: NSCoder) {
		// TODO empty stub
	}
} */