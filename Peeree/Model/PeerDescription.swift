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

public final class UserPeerInfo: /* LocalPeerInfo */ NSObject, NSSecureCoding {
    /// Key tag of secure enclave key pair used for communicating with REST API
    private static let PrivateKeyTag = "com.peeree.keys.restkey.private".data(using: .utf8)!
    private static let PublicKeyTag = "com.peeree.keys.restkey.public".data(using: .utf8)!
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
    
    public static func delete() {
        UserDefaults.standard.removeObject(forKey: PrefKey)
        Singleton.sharedInstance = UserPeerInfo()
    }
    
    @objc public static var supportsSecureCoding : Bool { return true }
    
    public var pictureResourceURL: URL {
        // Create a file path to our documents directory
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        return URL(fileURLWithPath: paths[0]).appendingPathComponent(UserPeerInfo.PortraitFileName)
    }
    
    private var _peer: PeerInfo
    
    public /* override */ var peer: PeerInfo {
        get { return _peer }
        set {
//            assert(peer == oldValue) cannot assert here as we override this from AccountController
            _peer = newValue
            _peer.lastChanged = Date()
            dirtied()
        }
    }
    
    private var _keyPair: KeyPair
    public var keyPair: KeyPair {
        get { return _keyPair }
    }
    
    /// must only be done by AccountController when new account is created
    public var peerID: PeerID {
        get { return peer.peerID }
        set {
            peer = peer.copy(to: newValue)
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
			}
		}
    }
	
	private override init() {
		dateOfBirth = nil
        try? AsymmetricPublicKey.removeFromKeychain(tag: UserPeerInfo.PublicKeyTag, keyType: PeerInfo.KeyType, size: PeerInfo.KeySize)
        try? AsymmetricPrivateKey.removeFromKeychain(tag: UserPeerInfo.PrivateKeyTag, keyType: PeerInfo.KeyType, size: PeerInfo.KeySize)
        self._keyPair = try! KeyPair(privateTag: UserPeerInfo.PrivateKeyTag, publicTag: UserPeerInfo.PublicKeyTag, type: PeerInfo.KeyType, size: PeerInfo.KeySize, persistent: true)
        self._peer = PeerInfo(peerID: PeerID(), publicKey: _keyPair.publicKey, nickname: NSLocalizedString("New Peer", comment: "Placeholder for peer name."), gender: .female, age: nil, cgPicture: nil)
//        super.init(peer: PeerInfo(peerID: PeerID(), publicKey: keyPair.publicKey, nickname: NSLocalizedString("New Peer", comment: "Placeholder for peer name."), gender: .female, age: nil, cgPicture: nil))
		super.init()
		archiveObjectInUserDefs(self, forKey: UserPeerInfo.PrefKey)
	}

    @objc required public init?(coder aDecoder: NSCoder) {
        dateOfBirth = aDecoder.decodeObject(of: NSDate.self, forKey: UserPeerInfo.DateOfBirthKey) as Date?
        guard let peerID = aDecoder.decodeObject(of: NSUUID.self, forKey: CBUUID.LocalPeerIDCharacteristicID.uuidString) else { return nil }
        guard let mainData = decode(aDecoder, characteristicID: CBUUID.AggregateCharacteristicID) else { return nil }
        guard let nicknameData = decode(aDecoder, characteristicID: CBUUID.NicknameCharacteristicID) else { return nil }
        guard let keyPair = try? KeyPair(fromKeychainWith: UserPeerInfo.PrivateKeyTag, publicTag: UserPeerInfo.PublicKeyTag, type: PeerInfo.KeyType, size: PeerInfo.KeySize) else { return nil }
        let lastChangedData = decode(aDecoder, characteristicID: CBUUID.LastChangedCharacteristicID)
        
        //        let uuid = aDecoder.decodeObject(of: NSUUID.self, forKey: PeerInfo.CodingKey.beaconUUID.rawValue)
        //        var characterTraits: [CharacterTrait]
        //        if let decodedTraits = aDecoder.decodeObject(of: NSArray.self, forKey: PeerInfo.CodingKey.traits.rawValue) as? [CharacterTraitCoding] {
        //            characterTraits = CharacterTraitCoding.structArray(decodedTraits)
        //        } else {
        //            characterTraits = CharacterTrait.standardTraits
        //        }
        
        guard let __peer = PeerInfo(peerID: peerID as PeerID, publicKey: keyPair.publicKey, aggregateData: mainData as Data, nicknameData: nicknameData as Data, lastChangedData: lastChangedData as Data?) else { return nil }
        _peer = __peer
        _keyPair = keyPair
        
        let pictureData = aDecoder.decodeObject(of: NSData.self, forKey: PeerInfo.CodingKey.picture.rawValue)
        let picture = pictureData != nil ? CGImage(jpegDataProviderSource: CGDataProvider(data: pictureData!)!, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent) : nil
        _peer.cgPicture = picture
    }
    
    @objc public func encode(with aCoder: NSCoder) {
        aCoder.encode(peer.peerID, forKey: CBUUID.LocalPeerIDCharacteristicID.uuidString)
        for characteristicID in [CBUUID.AggregateCharacteristicID, CBUUID.NicknameCharacteristicID, CBUUID.LastChangedCharacteristicID] {
            guard let data = peer.getCharacteristicValue(of: characteristicID) else { continue }
            encodeIt(aCoder, characteristicID: characteristicID, data: data)
        }
        if let image = peer.cgPicture {
            let data = NSMutableData()
            if let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                if CGImageDestinationFinalize(dest) {
                    aCoder.encode(data, forKey: PeerInfo.CodingKey.picture.rawValue)
                }
            }
        }
        aCoder.encode(dateOfBirth, forKey: UserPeerInfo.DateOfBirthKey)
        //        aCoder.encode(CharacterTraitCoding.codingArray(peer.characterTraits), forKey: PeerInfo.CodingKey.traits.rawValue)
        //        if let uuid = peer.iBeaconUUID {
        //            aCoder.encode(uuid as NSUUID, forKey: PeerInfo.CodingKey.beaconUUID.rawValue)
        //        }
    }
	
	public func dirtied() {
        archiveObjectInUserDefs(self, forKey: UserPeerInfo.PrefKey)
        // TODO turn it off and on again to make others reload our data
        // this is actually too dirty and error-prone to do from here
//        if PeeringController.shared.peering {
//            PeeringController.shared.peering = false
//            PeeringController.shared.peering = true
//        }
	}
}

private func decode(_ aDecoder: NSCoder, characteristicID: CBUUID) -> NSData? {
    return aDecoder.decodeObject(of: NSData.self, forKey: characteristicID.uuidString)
}

private func encodeIt(_ aCoder: NSCoder, characteristicID: CBUUID, data: Data) {
    return aCoder.encode(data as NSData, forKey: characteristicID.uuidString)
}

/* public class LocalPeerInfo: NSObject, NSSecureCoding {
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
        guard let peerID = aDecoder.decodeObject(of: NSUUID.self, forKey: CBUUID.LocalPeerIDCharacteristicID.uuidString) else { return nil }
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
        aCoder.encode(peer.peerID, forKey: CBUUID.LocalPeerIDCharacteristicID.uuidString)
        for characteristicID in [CBUUID.AggregateCharacteristicID, CBUUID.NicknameCharacteristicID, CBUUID.LastChangedCharacteristicID] {
            guard let data = peer.getCharacteristicValue(of: characteristicID) else { continue }
            encodeIt(aCoder, characteristicID: characteristicID, data: data)
        }
        if let image = peer.cgPicture {
            let data = NSMutableData()
            if let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
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
} */

public struct PeerInfo: Equatable {
    fileprivate enum CodingKey : String {
        case peerID, nickname, hasPicture, gender, age, status, traits, version, beaconUUID, picture, lastChanged, publicKey
    }
    
    public static let MinAge = 18, MaxAge = 80
    /// postgres can store strings up to this length very efficiently
    public static let MaxEmailSize = 126
    /// 4 BLE packets
    public static let MaxNicknameSize = 80
    public static let KeyType = kSecAttrKeyTypeEC // kSecAttrKeyTypeECSECPrimeRandom
    public static let KeySize = 256 // SecKeySizes.secp256r1.rawValue as AnyObject, only available on macOS...
    
    public enum Gender: String, CaseIterable {
        case male, female, queer
        
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
    
//    public struct AuthenticationStatus: OptionSet {
//        public let rawValue: Int
//        
//        /// we authenticated ourself to the peer
//        public static let to    = AuthenticationStatus(rawValue: 1 << 0)
//        /// the peer authenticated himself to us
//        public static let from  = AuthenticationStatus(rawValue: 1 << 1)
//        
//        public static let full: AuthenticationStatus = [.to, .from]
//        
//        public init(rawValue: Int) {
//            self.rawValue = rawValue
//        }
//    }
    
    public let peerID: PeerID
    
    /// being a constant ensures that the public key is not overwritten after it was verified
    public let publicKey: AsymmetricPublicKey
    
    public var verified = false
    
//    var authenticationStatus: AuthenticationStatus = []
    
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
        return AccountController.shared.hasPinMatch(self.peerID)
    }
    
    public var pinned: Bool {
        return AccountController.shared.isPinned(self)
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
    
    public var verificationStatus: String {
        if verified {
            return NSLocalizedString("verified", comment: "Verification status of peer")
        } else {
            return NSLocalizedString("not verified", comment: "Verification status of peer")
        }
    }
    
    public var summary: String {
        if age != nil {
            let format = NSLocalizedString("%d, %@ - %@ (%@)", comment: "Text describing the peers age, gender, pin and verification status")
            return String(format: format, age!, gender.localizedRawValue, pinStatus, verificationStatus)
        } else {
            let format = NSLocalizedString("%@ - %@ (%@)", comment: "Text describing the peers gender, pin and verification status")
            return String(format: format, gender.localizedRawValue, pinStatus, verificationStatus)
        }
    }
    
    var aggregateData: Data {
        get {
            let ageByte = UInt8(age ?? 0)
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
    
    var publicKeyData: Data { return try! publicKey.externalRepresentation() }
    
    var idData: Data { return peerID.encode() }
    
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
        case CBUUID.LocalPeerIDCharacteristicID:
            return idData
        case CBUUID.AggregateCharacteristicID:
            return aggregateData
        case CBUUID.LastChangedCharacteristicID:
            return lastChangedData
        case CBUUID.NicknameCharacteristicID:
            return nicknameData
        case CBUUID.PublicKeyCharacteristicID:
            return publicKeyData
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
    
    func copy(to: PeerID) -> PeerInfo {
        return PeerInfo(peerID: to, publicKey: publicKey, nickname: nickname, gender: gender, age: age, cgPicture: cgPicture)
    }
    
    init(peerID: PeerID, publicKey: AsymmetricPublicKey, nickname: String, gender: PeerInfo.Gender, age: Int?, cgPicture: CGImage?) {
        self.peerID = peerID
        self.publicKey = publicKey
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
    
    init?(peerID: PeerID, publicKeyData: Data, aggregateData: Data, nicknameData: Data, lastChangedData: Data?) {
        do {
            let publicKey = try AsymmetricPublicKey(from: publicKeyData, type: PeerInfo.KeyType, size: PeerInfo.KeySize)
            self.init(peerID: peerID, publicKey: publicKey, aggregateData: aggregateData, nicknameData: nicknameData, lastChangedData: lastChangedData)
        } catch {
            NSLog("ERR: creating public key from data: \(error)")
            return nil
        }
    }
    
    init?(peerID: PeerID, publicKey: AsymmetricPublicKey, aggregateData: Data, nicknameData: Data, lastChangedData: Data?) {
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
        
        self.publicKey = publicKey
        
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
