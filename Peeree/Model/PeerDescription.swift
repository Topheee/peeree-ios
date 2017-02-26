//
//  PeerDescription.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics
import ImageIO

/**
 Class used only for unit testing.
 */
class TestPeerInfo: NetworkPeerInfo {
    init(peerID: PeerID) {
        var rand = arc4random()
        let age: Int? = rand % 2 == 0 ? PeerInfo.MinAge + Int(rand % UInt32(PeerInfo.MaxAge - PeerInfo.MinAge)) : nil
        let relationshipStatus = PeerInfo.RelationshipStatus.inRelationship
        var characterTraits = CharacterTrait.standardTraits
        for index in 0..<characterTraits.count {
            characterTraits[index].applies = CharacterTrait.ApplyType.values[Int(rand % 4)]
            rand = arc4random()
        }
        let peer = PeerInfo(peerID: peerID, nickname: peerID.uuidString, gender: PeerInfo.Gender.female, age: age, relationshipStatus: relationshipStatus, characterTraits: characterTraits, version: "1.0", iBeaconUUID: UUID(), lastChanged: Date(), _hasPicture: true /* rand % 5000 > 2500 */, cgPicture: nil)
        super.init(peer: peer)
    }
    
    @objc required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

public final class UserPeerInfo: LocalPeerInfo {
	private static let PrefKey = "UserPeerInfo"
    private static let DateOfBirthKey = "dateOfBirth"
    private static let PortraitFileName = "UserPortrait"
    
    private static var __once: () = { () -> Void in
        Singleton.sharedInstance = unarchiveObjectFromUserDefs(PrefKey) ?? UserPeerInfo()
    }()
    private struct Singleton {
        static var sharedInstance: UserPeerInfo!
    }
	static var instance: UserPeerInfo {
        _ = UserPeerInfo.__once
        
        return Singleton.sharedInstance
	}
    
    var pictureResourceURL: URL {
        // Create a file path to our documents directory
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        return URL(fileURLWithPath: paths[0]).appendingPathComponent(UserPeerInfo.PortraitFileName)
    }
    
    override var peer: PeerInfo {
        didSet {
            assert(peer == oldValue)
            dirtied()
        }
    }
	
	var dateOfBirth: Date? {
		didSet {
			if dateOfBirth != oldValue {
                if let birth = dateOfBirth {
                    peer.age = (Calendar.current as NSCalendar).components(NSCalendar.Unit.year, from: birth, to: Date(), options: []).year
                } else {
                    peer.age = nil
                }
                
				dirtied()
			}
		}
    }
    
    var nickname: String {
        get { return peer.nickname }
        set {
            guard newValue != "" && newValue != peer.nickname else { return }
            
            peer.nickname = newValue
            dirtied()
        }
    }
	var age: Int? { return peer.age }
	var gender: PeerInfo.Gender {
        get { return peer.gender }
        set { if newValue != peer.gender { peer.gender = newValue; dirtied() } }
    }
    var iBeaconUUID: UUID? {
        get { return peer.iBeaconUUID }
        set { if newValue != peer.iBeaconUUID { peer.iBeaconUUID = newValue; dirtied() } }
    }
    var relationshipStatus: PeerInfo.RelationshipStatus {
        get { return peer.relationshipStatus }
        set { if newValue != peer.relationshipStatus { peer.relationshipStatus = newValue; dirtied() } }
    }
    var characterTraits: [CharacterTrait] {
        get { return peer.characterTraits }
        set { peer.characterTraits = newValue; dirtied() }
    }
	
	private init() {
		dateOfBirth = Date(timeIntervalSinceNow: -3600*24*365*18)
        super.init(peer: PeerInfo(peerID: PeerID(), nickname: "Unknown", gender: .female, age: nil, relationshipStatus: .inRelationship, characterTraits: CharacterTrait.standardTraits, version: "1.0", iBeaconUUID: nil, lastChanged: Date(), _hasPicture: false, cgPicture: nil))
	}

	@objc required public init?(coder aDecoder: NSCoder) {
		dateOfBirth = aDecoder.decodeObject(of: NSDate.self, forKey: UserPeerInfo.DateOfBirthKey) as? Date ?? Date(timeIntervalSinceNow: -3600*24*365*18)
	    super.init(coder: aDecoder)
    }
    
    @objc override public func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(dateOfBirth, forKey: UserPeerInfo.DateOfBirthKey)
    }
	
//	private func warnIdentityChange(_ proceedHandler: ((UIAlertAction) -> Void)?, cancelHandler: ((UIAlertAction) -> Void)?, completionHandler: (() -> Void)?) {
//		let alertController = UIAlertController(title: NSLocalizedString("Change of Identity", comment: "Title message of alerting the user that he is about to change the unambigous representation of himself in the Peeree world."), message: NSLocalizedString("You are about to change your identification. If you continue others, even those who pinned you, won't recognize you any more. This is also the case if you again reset your name to the original one. However, your pins all keep being valid!", comment: "Description of 'Change of Identity'"), preferredStyle: .actionSheet)
//		alertController.addAction(UIAlertAction(title: NSLocalizedString("Change Identity", comment: "Button text for choosing a new Peeree identity."), style: .destructive, handler: proceedHandler))
//		alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: cancelHandler))
//        alertController.present(completionHandler)
//	}
	
	func dirtied() {
		archiveObjectInUserDefs(self, forKey: UserPeerInfo.PrefKey)
	}
}

public class LocalPeerInfo: NSObject, NSSecureCoding {
    var peer: PeerInfo
    var sentPinStatus = false
    var pinStatusAcknowledged = false
    
    var cgPicture: CGImage? {
        get { return peer.cgPicture }
        set { peer.cgPicture = newValue }
    }
    
    @objc public static var supportsSecureCoding : Bool {
        return true
    }
    
    private override init() {
        fatalError()
    }
    
    init(peer: PeerInfo) {
        self.peer = peer
    }
    
    @objc required public init?(coder aDecoder: NSCoder) {
        guard let peerID = aDecoder.decodeObject(of: NSUUID.self, forKey: PeerInfo.CodingKey.peerID.rawValue) else { return nil }
        guard let rawGenderValue = aDecoder.decodeObject(of: NSString.self, forKey: PeerInfo.CodingKey.gender.rawValue) as? String else { return nil }
        guard let gender = PeerInfo.Gender(rawValue: rawGenderValue) else { return nil }
        
        let nickname = aDecoder.decodeObject(of: NSString.self, forKey: PeerInfo.CodingKey.nickname.rawValue) as? String ?? "Unknown"
        let lastChanged = aDecoder.decodeObject(of: NSDate.self, forKey: PeerInfo.CodingKey.lastChanged.rawValue) as? Date ?? Date()
        let version = aDecoder.decodeObject(of: NSString.self, forKey: PeerInfo.CodingKey.version.rawValue) as? String ?? "1.0"
        let uuid = aDecoder.decodeObject(of: NSUUID.self, forKey: PeerInfo.CodingKey.beaconUUID.rawValue)
        var characterTraits: [CharacterTrait]
        if let decodedTraits = aDecoder.decodeObject(of: NSArray.self, forKey: PeerInfo.CodingKey.traits.rawValue) as? [CharacterTraitCoding] {
            characterTraits = CharacterTraitCoding.structArray(decodedTraits)
        } else {
            characterTraits = CharacterTrait.standardTraits
        }
        let pictureData = aDecoder.decodeObject(of: NSData.self, forKey: PeerInfo.CodingKey.picture.rawValue)
        let picture = pictureData != nil ? CGImage(jpegDataProviderSource: CGDataProvider(data: pictureData!)!, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent) : nil
        let age: Int? = aDecoder.containsValue(forKey: PeerInfo.CodingKey.age.rawValue) ? aDecoder.decodeInteger(forKey: PeerInfo.CodingKey.age.rawValue) : nil
        
        var relationshipStatus: PeerInfo.RelationshipStatus
        if let rawStatusValue = aDecoder.decodeObject(of: NSString.self, forKey: PeerInfo.CodingKey.status.rawValue) as? String {
            relationshipStatus = PeerInfo.RelationshipStatus(rawValue:rawStatusValue) ?? PeerInfo.RelationshipStatus.noComment
        } else {
            relationshipStatus = PeerInfo.RelationshipStatus.noComment
        }
        
        peer = PeerInfo(peerID: peerID as PeerID, nickname: nickname, gender: gender, age: age, relationshipStatus: relationshipStatus, characterTraits: characterTraits, version: version, iBeaconUUID: uuid as UUID?, lastChanged: lastChanged, _hasPicture: picture != nil, cgPicture: picture)
    }
    
    @objc public func encode(with aCoder: NSCoder) {
        aCoder.encode(peer.peerID, forKey: PeerInfo.CodingKey.peerID.rawValue)
        aCoder.encode(peer.nickname, forKey: PeerInfo.CodingKey.nickname.rawValue)
        if let image = peer.cgPicture {
            let data = NSMutableData()
            if let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil) // TODO use options
                if CGImageDestinationFinalize(dest) {
                    aCoder.encode(data, forKey: PeerInfo.CodingKey.picture.rawValue)
                }
            }
        }
        aCoder.encode(peer.gender.rawValue, forKey: PeerInfo.CodingKey.gender.rawValue)
        aCoder.encode(peer.relationshipStatus.rawValue, forKey: PeerInfo.CodingKey.status.rawValue)
        aCoder.encode(peer.version, forKey: PeerInfo.CodingKey.version.rawValue)
        aCoder.encode(CharacterTraitCoding.codingArray(peer.characterTraits), forKey: PeerInfo.CodingKey.traits.rawValue)
        aCoder.encode(peer.lastChanged, forKey: PeerInfo.CodingKey.lastChanged.rawValue)
        if let age = peer.age {
            aCoder.encode(age, forKey: PeerInfo.CodingKey.age.rawValue)
        }
        if let uuid = peer.iBeaconUUID {
            aCoder.encode(uuid as NSUUID, forKey: PeerInfo.CodingKey.beaconUUID.rawValue)
        }
    }
}

public /* final */ class NetworkPeerInfo: NSObject, NSCoding /* NSSecureCoding */ {
    let peer: PeerInfo
    
//    @objc static var supportsSecureCoding : Bool {
//        return true
//    }
    
    private override init() {
        fatalError()
    }
    
    init(peer: PeerInfo) {
        self.peer = peer
    }
    
    @objc required public init?(coder aDecoder: NSCoder) {
        guard let peerID = aDecoder.decodeObject(of: NSUUID.self, forKey: PeerInfo.CodingKey.peerID.rawValue) else { return nil }
        guard let rawGenderValue = aDecoder.decodeObject(of: NSString.self, forKey: PeerInfo.CodingKey.gender.rawValue) as? String else { return nil }
        guard let gender = PeerInfo.Gender(rawValue: rawGenderValue) else { return nil }
        
        let nickname = aDecoder.decodeObject(of: NSString.self, forKey: PeerInfo.CodingKey.nickname.rawValue) as? String ?? "Unknown"
        let lastChanged = aDecoder.decodeObject(of: NSDate.self, forKey: PeerInfo.CodingKey.lastChanged.rawValue) as? Date ?? Date()
        let version = aDecoder.decodeObject(of: NSString.self, forKey: PeerInfo.CodingKey.version.rawValue) as? String ?? "1.0"
        let uuid = aDecoder.decodeObject(of: NSUUID.self, forKey: PeerInfo.CodingKey.beaconUUID.rawValue)
        var characterTraits: [CharacterTrait]
        if let decodedTraits = aDecoder.decodeObject(of: NSArray.self, forKey: PeerInfo.CodingKey.traits.rawValue) as? [CharacterTraitCoding] {
            characterTraits = CharacterTraitCoding.structArray(decodedTraits)
        } else {
            characterTraits = CharacterTrait.standardTraits
        }
        let hasPicture = aDecoder.decodeBool(forKey: PeerInfo.CodingKey.hasPicture.rawValue)
        let age: Int? = aDecoder.containsValue(forKey: PeerInfo.CodingKey.age.rawValue) ? aDecoder.decodeInteger(forKey: PeerInfo.CodingKey.age.rawValue) : nil

        var relationshipStatus: PeerInfo.RelationshipStatus
        if let rawStatusValue = aDecoder.decodeObject(of: NSString.self, forKey: PeerInfo.CodingKey.status.rawValue) as? String {
            relationshipStatus = PeerInfo.RelationshipStatus(rawValue:rawStatusValue) ?? PeerInfo.RelationshipStatus.noComment
        } else {
            relationshipStatus = PeerInfo.RelationshipStatus.noComment
        }
        
        peer = PeerInfo(peerID: peerID as PeerID, nickname: nickname, gender: gender, age: age, relationshipStatus: relationshipStatus, characterTraits: characterTraits, version: version, iBeaconUUID: uuid as UUID?, lastChanged: lastChanged, _hasPicture: hasPicture, cgPicture: nil)
    }
    
    @objc public func encode(with aCoder: NSCoder) {
        aCoder.encode(peer.peerID, forKey: PeerInfo.CodingKey.peerID.rawValue)
        aCoder.encode(peer.nickname, forKey: PeerInfo.CodingKey.nickname.rawValue)
        aCoder.encode(peer.hasPicture, forKey: PeerInfo.CodingKey.hasPicture.rawValue)
        aCoder.encode(peer.gender.rawValue, forKey: PeerInfo.CodingKey.gender.rawValue)
        aCoder.encode(peer.relationshipStatus.rawValue, forKey: PeerInfo.CodingKey.status.rawValue)
        aCoder.encode(peer.version, forKey: PeerInfo.CodingKey.version.rawValue)
        aCoder.encode(CharacterTraitCoding.codingArray(peer.characterTraits), forKey: PeerInfo.CodingKey.traits.rawValue)
        aCoder.encode(peer.lastChanged, forKey: PeerInfo.CodingKey.lastChanged.rawValue)
        if let age = peer.age {
            aCoder.encode(age, forKey: PeerInfo.CodingKey.age.rawValue)
        }
        if let uuid = peer.iBeaconUUID {
            aCoder.encode(uuid as NSUUID, forKey: PeerInfo.CodingKey.beaconUUID.rawValue)
        }
    }
}

public struct PeerInfo: Equatable {
    fileprivate enum CodingKey : String {
        case peerID, nickname, hasPicture, gender, age, status, traits, version, beaconUUID, picture, lastChanged
    }
    
    static let MinAge = 13, MaxAge = 100
    
    enum Gender: String {
        case male, female, queer
        
        static let values = [male, female, queer]
        
        /*
         *  For genstrings
         *
         *  NSLocalizedString("male", comment: "Male gender.")
         *  NSLocalizedString("female", comment: "Female gender.")
         *  NSLocalizedString("queer", comment: "Gender type for everyone who does not fit into the other two genders.")
         */
    }
    
    enum RelationshipStatus: String {
        case noComment, single, married, inRelationship
        
        static let values = [noComment, single, married, inRelationship]
        
        /*
         * For genstrings
         *
         *  NSLocalizedString("noComment", comment: "The user does not want to expose his relationship status.")
         *  NSLocalizedString("single", comment: "The user is not in an relationship nor was married.")
         *  NSLocalizedString("married", comment: "The user is married.")
         *  NSLocalizedString("inRelationship", comment: "The user is already in some kind of relationship.")
         */
    }
    
    let peerID: PeerID
    
    var nickname: String
    
    var gender = Gender.female
    var age: Int?
    var relationshipStatus = RelationshipStatus.noComment
    
    var characterTraits: [CharacterTrait]
    /**
     *	Version information with the same format as Apple's dylib version format. This is used to test the compatibility of two Peeree apps exchanging data via bluetooth.
     */
    var version = "1.0"
    
    var iBeaconUUID: UUID? = nil // TODO Swift 3: change to UUID Swift type, as it is a struct
    
    var lastChanged = Date()
    
    fileprivate var _hasPicture: Bool = false
    var hasPicture: Bool {
        return _hasPicture
    }
    
    var cgPicture: CGImage? {
        didSet {
            _hasPicture = cgPicture != nil
        }
    }

    var pinMatched: Bool {
        return PeeringController.shared.hasPinMatch(peerID)
    }
    
    var pinned: Bool {
        return PeeringController.shared.isPinned(peerID)
    }
    
    var pinStatus: String {
        if pinned {
            if pinMatched {
                return NSLocalizedString("Pin Match!", comment: "Two peers have pinned each other")
            } else {
                return NSLocalizedString("Pinned.", comment: "The user marked someone as interesting")
            }
        } else {
            return NSLocalizedString("Not yet pinned.", comment: "The user did not yet marked someone as interesting")
        }
    }
    
    var summary: String {
        if age != nil {
            let format = NSLocalizedString("%d years old, %@ - %@", comment: "Text describing the peers age, gender and pin status.")
            return String(format: format, age!, gender.localizedRawValue, pinStatus)
        } else {
            let format = NSLocalizedString("%@ - %@", comment: "Text describing the peers gender and pin status.")
            return String(format: format, gender.localizedRawValue, pinStatus)
        }
    }
    
//    func copyToNewID(_ peerID: MCPeerID) -> PeerInfo {
//        return PeerInfo(peerID: peerID, gender: gender, age: age, relationshipStatus: relationshipStatus, characterTraits: characterTraits, version: version, iBeaconUUID: iBeaconUUID, lastChanged: lastChanged, _hasPicture:
//            _hasPicture, _picture: _picture)
//    }
}

public func ==(lhs: PeerInfo, rhs: PeerInfo) -> Bool {
    return lhs.peerID == rhs.peerID
}

func ==(lhs: PeerInfo, rhs: PeerID) -> Bool {
    return lhs.peerID == rhs
}

func ==(lhs: PeerID, rhs: PeerInfo) -> Bool {
    return lhs == rhs.peerID
}
