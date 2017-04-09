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
import CoreBluetooth.CBUUID

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
	public static var instance: UserPeerInfo {
        _ = UserPeerInfo.__once
        
        return Singleton.sharedInstance
	}
    
    public var pictureResourceURL: URL {
        // Create a file path to our documents directory
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        return URL(fileURLWithPath: paths[0]).appendingPathComponent(UserPeerInfo.PortraitFileName)
    }
    
    public override var peer: PeerInfo {
        didSet {
            assert(peer == oldValue)
            dirtied()
        }
    }
	
	public var dateOfBirth: Date? {
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
    
    public var nickname: String {
        get { return peer.nickname }
        set {
            guard newValue != "" && newValue != peer.nickname else { return }
            
            peer.nickname = newValue
            dirtied()
        }
    }
	public var age: Int? { return peer.age }
	public var gender: PeerInfo.Gender {
        get { return peer.gender }
        set { if newValue != peer.gender { peer.gender = newValue; dirtied() } }
    }
    public var characterTraits: [CharacterTrait] {
        get { return peer.characterTraits }
        set { peer.characterTraits = newValue; dirtied() }
    }
	
	private init() {
		dateOfBirth = nil
        super.init(peer: PeerInfo(peerID: PeerID(), nickname: NSLocalizedString("New Peer", comment: "Placeholder for peer name."), gender: .female, age: nil, cgPicture: nil))
	}

	@objc required public init?(coder aDecoder: NSCoder) {
		dateOfBirth = aDecoder.decodeObject(of: NSDate.self, forKey: UserPeerInfo.DateOfBirthKey) as Date?
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
	
	public func dirtied() {
		archiveObjectInUserDefs(self, forKey: UserPeerInfo.PrefKey)
	}
}

private func decode(_ aDecoder: NSCoder, characteristicID: CBUUID) -> NSData? {
    return aDecoder.decodeObject(of: NSData.self, forKey: characteristicID.uuidString)
}

private func encodeIt(_ aCoder: NSCoder, characteristicID: CBUUID, data: Data) {
    return aCoder.encode(data as NSData, forKey: characteristicID.uuidString)
}

public class LocalPeerInfo: NSObject, NSSecureCoding {
    var peer: PeerInfo
    
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
        guard let peerID = aDecoder.decodeObject(of: NSUUID.self, forKey: CBUUID.LocalUUIDCharacteristicID.uuidString) else { return nil }
        guard let mainData = decode(aDecoder, characteristicID: CBUUID.AggregateCharacteristicID) else { return nil }
        guard let nicknameData = decode(aDecoder, characteristicID: CBUUID.NicknameCharacteristicID) else { return nil }
        let lastChangedData = decode(aDecoder, characteristicID: CBUUID.LastChangedCharacteristicID)
        
//        let uuid = aDecoder.decodeObject(of: NSUUID.self, forKey: PeerInfo.CodingKey.beaconUUID.rawValue)
//        var characterTraits: [CharacterTrait]
//        if let decodedTraits = aDecoder.decodeObject(of: NSArray.self, forKey: PeerInfo.CodingKey.traits.rawValue) as? [CharacterTraitCoding] {
//            characterTraits = CharacterTraitCoding.structArray(decodedTraits)
//        } else {
//            characterTraits = CharacterTrait.standardTraits
//        }
        
        guard let _peer = PeerInfo(peerID: peerID as PeerID, aggregateData: mainData as Data, nicknameData: nicknameData as Data, lastChangedData: lastChangedData as Data?) else { return nil }
        peer = _peer

        let pictureData = aDecoder.decodeObject(of: NSData.self, forKey: PeerInfo.CodingKey.picture.rawValue)
        let picture = pictureData != nil ? CGImage(jpegDataProviderSource: CGDataProvider(data: pictureData!)!, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent) : nil
        peer.cgPicture = picture
    }
    
    @objc public func encode(with aCoder: NSCoder) {
        aCoder.encode(peer.peerID, forKey: CBUUID.LocalUUIDCharacteristicID.uuidString)
        for characteristicID in [CBUUID.AggregateCharacteristicID, CBUUID.NicknameCharacteristicID, CBUUID.LastChangedCharacteristicID] {
            guard let data = peer.getCharacteristicValue(of: characteristicID) else { continue }
            encodeIt(aCoder, characteristicID: characteristicID, data: data)
        }
        if let image = peer.cgPicture {
            let data = NSMutableData()
            if let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil) // TODO use options
                if CGImageDestinationFinalize(dest) {
                    aCoder.encode(data, forKey: PeerInfo.CodingKey.picture.rawValue)
                }
            }
        }
//        aCoder.encode(CharacterTraitCoding.codingArray(peer.characterTraits), forKey: PeerInfo.CodingKey.traits.rawValue)
//        if let uuid = peer.iBeaconUUID {
//            aCoder.encode(uuid as NSUUID, forKey: PeerInfo.CodingKey.beaconUUID.rawValue)
//        }
    }
}

public struct PeerInfo: Equatable {
    fileprivate enum CodingKey : String {
        case peerID, nickname, hasPicture, gender, age, status, traits, version, beaconUUID, picture, lastChanged
    }
    
    public static let MinAge = 13, MaxAge = 100
    
    public enum Gender: String {
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
    private enum GenderByte: UInt8 {
        case male, female, queer
    }
    
    public let peerID: PeerID
    
    public var nickname = ""
    
    public var gender = Gender.queer
    public var age: Int? = nil
    
    public var characterTraits: [CharacterTrait] = CharacterTrait.standardTraits
    /**
     *	Version information with the same format as Apple's dylib version format. This is used to test the compatibility of two Peeree apps exchanging data via bluetooth.
     */
    public var version = UInt8(0)
    
    public var lastChanged = Date.distantPast
    
    fileprivate var _hasPicture: Bool = false
    public var hasPicture: Bool {
        return _hasPicture
    }
    
    public var cgPicture: CGImage? {
        didSet {
            _hasPicture = cgPicture != nil
        }
    }

    public var pinMatched: Bool {
        return PeeringController.shared.hasPinMatch(peerID)
    }
    
    public var pinned: Bool {
        return PeeringController.shared.isPinned(peerID)
    }
    
    public var pinStatus: String {
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
    
    public var summary: String {
        if age != nil {
            let format = NSLocalizedString("%d years old, %@ - %@", comment: "Text describing the peers age, gender and pin status.")
            return String(format: format, age!, gender.localizedRawValue, pinStatus)
        } else {
            let format = NSLocalizedString("%@ - %@", comment: "Text describing the peers gender and pin status.")
            return String(format: format, gender.localizedRawValue, pinStatus)
        }
    }
    
    var aggregateData: Data {
        get {
            let ageByte = age != nil ? UInt8(age!) : UInt8(0)
            let genderByte: GenderByte = gender == .queer ? .queer : gender == .female ? .female : .male;
            return Data(bytes: [ageByte, genderByte.rawValue, UInt8(hasPicture), version])
        }
        set {
            if newValue.count > 0 {
                let _age = Int(newValue[0])
                if !(_age < PeerInfo.MinAge || _age > PeerInfo.MaxAge) {
                    age = _age
                }
            }
            if newValue.count > 1 {
                if let genderByte = GenderByte(rawValue: newValue[1]) {
                    switch genderByte {
                    case .female:
                        gender = .female
                    case .queer:
                        gender = .queer
                    case .male:
                        gender = .male
                    }
                }
            }
            if newValue.count > 2 {
                _hasPicture = Bool(newValue[2])
            }
            if newValue.count > 3 {
                version = newValue[3]
            }
        }
    }
    
    var nicknameData: Data {
        get {
            return nickname.data(prefixedEncoding: nickname.smallestEncoding)!
        }
        set {
            nickname = String(dataPrefixedEncoding: newValue) ?? ""
        }
    }
    
    var idData: Data { return peerID.uuidString.data(using: PeerManager.uuidEncoding)! }
    
    var lastChangedData: Data {
        get {
            var changed = lastChanged.timeIntervalSince1970
            return Data(bytes: &changed, count: MemoryLayout<TimeInterval>.size)
        }
        set {
            guard newValue.count >= MemoryLayout<TimeInterval>.size else { return }
            
            var changed: TimeInterval = 0.0
            withUnsafeMutableBytes(of: &changed) { pointer in
                pointer.copyBytes(from: newValue)
            }
            lastChanged = Date(timeIntervalSince1970: changed)
        }
    }
    
    func getCharacteristicValue(of characteristicID: CBUUID) -> Data? {
        switch characteristicID {
        case CBUUID.LocalUUIDCharacteristicID:
            return idData
        case CBUUID.AggregateCharacteristicID:
            return aggregateData
        case CBUUID.LastChangedCharacteristicID:
            return lastChangedData
        case CBUUID.NicknameCharacteristicID:
            return nicknameData
        default:
            return nil
        }
    }
    
    mutating func setCharacteristicValue(of characteristicID: CBUUID, to: Data) {
        switch characteristicID {
        case CBUUID.AggregateCharacteristicID:
            aggregateData = to
        case CBUUID.LastChangedCharacteristicID:
            lastChangedData = to
        case CBUUID.NicknameCharacteristicID:
            nicknameData = to
        default:
            break
        }
    }
    
    init(peerID: PeerID, nickname: String, gender: PeerInfo.Gender, age: Int?, cgPicture: CGImage?) {
        self.peerID = peerID
        self.nickname = nickname
        self.gender = gender
        self.age = age
        self.cgPicture = cgPicture
    }
    
//    init?(peerID: PeerID, aggregateData: Data, nicknameData: Data, lastChangedData: Data?) {
//        guard aggregateData.count > 2 else { return nil }
//        self.peerID = peerID
//        self.aggregateData = aggregateData
//        self.nicknameData = nicknameData
//        print("new nickname: \(nickname)")
//        if nickname == "" { return nil }
//        guard let changedData = lastChangedData else { return }
//        self.lastChangedData = changedData
//    }
    
    init?(peerID: PeerID, aggregateData: Data, nicknameData: Data, lastChangedData: Data?) {
        guard aggregateData.count > 2 else { return nil }
        self.peerID = peerID
        // same as self.aggregateData = aggregateData
        if aggregateData.count > 0 {
            let _age = Int(aggregateData[0])
            if !(_age < PeerInfo.MinAge || _age > PeerInfo.MaxAge) {
                age = _age
            }
        }
        if aggregateData.count > 1 {
            if let genderByte = GenderByte(rawValue: aggregateData[1]) {
                switch genderByte {
                case .female:
                    gender = .female
                case .queer:
                    gender = .queer
                case .male:
                    gender = .male
                }
            }
        }
        if aggregateData.count > 2 {
            _hasPicture = Bool(aggregateData[2])
        }
        if aggregateData.count > 3 {
            version = aggregateData[3]
        }
        
        // same as self.nicknameData = nicknameData
        nickname = String(dataPrefixedEncoding: nicknameData) ?? ""
        if nickname == "" { return nil }
        
        // same as self.lastChangedData = lastChangedData
        guard let changedData = lastChangedData else { return }
        guard changedData.count >= MemoryLayout<TimeInterval>.size else { return }
        
        var changed: TimeInterval = 0.0
        withUnsafeMutableBytes(of: &changed) { pointer in
            pointer.copyBytes(from: changedData)
        }
        lastChanged = Date(timeIntervalSince1970: changed)
    }
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
