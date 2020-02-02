//
//  PeerDescription.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation
import ImageIO
import CoreBluetooth.CBUUID

public final class UserPeerManager: PeerManager {
	public static let PrefKey = "UserPeerManager"
	private static let PortraitFileName = "UserPortrait"
	fileprivate static let PrivateKeyTag = "com.peeree.keys.restkey.private".data(using: .utf8)!
	fileprivate static let PublicKeyTag = "com.peeree.keys.restkey.public".data(using: .utf8)!
	public static var instance = UserPeerManager()
	
	public static var pictureResourceURL: URL {
		// Create a file path to our documents directory
		let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
		return URL(fileURLWithPath: paths[0]).appendingPathComponent(UserPeerManager.PortraitFileName, isDirectory: false)
	}
	
	public static func delete() {
		UserDefaults.standard.removeObject(forKey: PrefKey)
		instance = UserPeerManager()
		instance.dirtied()
	}
	
	public static func define(peerID: PeerID) {
		instance = UserPeerManager(peerID: peerID)
		instance.dirtied()
	}
	
	private let localPeerInfo = unarchiveObjectFromUserDefs(UserPeerManager.PrefKey) ?? UserPeerInfo()
	
	private init() {
		super.init(peerID: localPeerInfo.peerID)
		if peerInfo!.hasPicture {
			if let provider = CGDataProvider(url: UserPeerManager.pictureResourceURL as CFURL) {
				cgPicture = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent)
			} else {
				NSLog("ERR: could not initialize CGDataProvider.")
			}
		}
	}
	
	// hide initializer
	override private init(peerID: PeerID) {
		super.init(peerID: peerID)
		localPeerInfo.peerID = peerID
	}
	
	/// always returns true to look good in preview
	override var verified: Bool {
		get { return true }
	}
	
	override public var cgPicture: CGImage? {
		didSet {
			peer.hasPicture = cgPicture != nil
		}
	}
	
	override public var peerInfo: PeerInfo? {
		return localPeerInfo.peer
	}
	
	public var peer: PeerInfo {
		get { return localPeerInfo.peer }
		set {
			localPeerInfo.peer = newValue
			dirtied()
		}
	}
	
	public var keyPair: KeyPair { return localPeerInfo._keyPair }
	public var dateOfBirth: Date? {
		get { return localPeerInfo.dateOfBirth }
		set { localPeerInfo.dateOfBirth = newValue; dirtied() }
	}
	
	public func dirtied() {
		archiveObjectInUserDefs(localPeerInfo, forKey: UserPeerManager.PrefKey)
	}
	
}

/*@objc(_TtC6PeereeP33_DB5622D9576691BD4650A5BF163822B512UserPeerInfo) private */ public final class UserPeerInfo: NSObject, NSSecureCoding {
    private static let DateOfBirthKey = "dateOfBirth"
	
    @objc public static var supportsSecureCoding : Bool { return true }
	
    private var _peer: PeerInfo
    
    public var peer: PeerInfo {
        get { return _peer }
        set {
//            assert(peer == oldValue) cannot assert here as we override this from AccountController
            _peer = newValue
            _peer.lastChanged = Date()
        }
    }
    
    fileprivate var _keyPair: KeyPair
    
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
                refreshAge()
			}
		}
    }
	
	fileprivate override init() {
		dateOfBirth = nil
		try? KeychainStore.removeFromKeychain(tag: UserPeerManager.PublicKeyTag, keyType: PeerInfo.KeyType, keyClass: kSecAttrKeyClassPublic, size: PeerInfo.KeySize)
		try? KeychainStore.removeFromKeychain(tag: UserPeerManager.PrivateKeyTag, keyType: PeerInfo.KeyType, keyClass: kSecAttrKeyClassPrivate, size: PeerInfo.KeySize)
		self._keyPair = try! KeyPair(label: "Peeree Identity", privateTag: UserPeerManager.PrivateKeyTag, publicTag: UserPeerManager.PublicKeyTag, type: PeerInfo.KeyType, size: PeerInfo.KeySize, persistent: true)
        self._peer = PeerInfo(peerID: PeerID(), publicKey: _keyPair.publicKey, nickname: NSLocalizedString("New Peereer", comment: "Placeholder for peer name."), gender: .female, age: nil, hasPicture: false)
	}

    @objc required public init?(coder aDecoder: NSCoder) {
        guard let peerID = aDecoder.decodeObject(of: NSUUID.self, forKey: CBUUID.LocalPeerIDCharacteristicID.uuidString) else { return nil }
        guard let mainData = decode(aDecoder, characteristicID: CBUUID.AggregateCharacteristicID) else { return nil }
        guard let nicknameData = decode(aDecoder, characteristicID: CBUUID.NicknameCharacteristicID) else { return nil }
        guard let keyPair = try? KeyPair(fromKeychainWith: UserPeerManager.PrivateKeyTag, publicTag: UserPeerManager.PublicKeyTag, type: PeerInfo.KeyType, size: PeerInfo.KeySize) else { return nil }
        let lastChangedData = decode(aDecoder, characteristicID: CBUUID.LastChangedCharacteristicID)
        
        guard let peer = PeerInfo(peerID: peerID as PeerID, publicKey: keyPair.publicKey, aggregateData: mainData as Data, nicknameData: nicknameData as Data, lastChangedData: lastChangedData as Data?) else { return nil }
        _peer = peer
        _keyPair = keyPair
		
		super.init()
        dateOfBirth = aDecoder.decodeObject(of: NSDate.self, forKey: UserPeerInfo.DateOfBirthKey) as Date?
    }
    
    @objc public func encode(with aCoder: NSCoder) {
        aCoder.encode(peer.peerID, forKey: CBUUID.LocalPeerIDCharacteristicID.uuidString)
        for characteristicID in [CBUUID.AggregateCharacteristicID, CBUUID.NicknameCharacteristicID, CBUUID.LastChangedCharacteristicID] {
            guard let data = peer.getCharacteristicValue(of: characteristicID) else { continue }
            encodeIt(aCoder, characteristicID: characteristicID, data: data)
        }
        aCoder.encode(dateOfBirth, forKey: UserPeerInfo.DateOfBirthKey)
    }
	
	private func refreshAge() {
		if let birth = dateOfBirth {
			peer.age = (Calendar.current as NSCalendar).components(NSCalendar.Unit.year, from: birth, to: Date(), options: []).year
		} else {
			peer.age = nil
		}
	}
}

private func decode(_ aDecoder: NSCoder, characteristicID: CBUUID) -> NSData? {
    return aDecoder.decodeObject(of: NSData.self, forKey: characteristicID.uuidString)
}

private func encodeIt(_ aCoder: NSCoder, characteristicID: CBUUID, data: Data) {
    return aCoder.encode(data as NSData, forKey: characteristicID.uuidString)
}

public struct PeerInfo: Equatable {
    public static let MinAge = 18, MaxAge = 80
    /// postgres can store strings up to this length very efficiently
    public static let MaxEmailSize = 126
    /// 1 non-extended BLE packet length would be 27. Since most devices seem to support extended packets, we chose something higher and cap it on the phy level
    public static let MaxNicknameSize = 184
    public static let KeyType = kSecAttrKeyTypeEC
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
    
    public var hasPicture: Bool = false
	
	public var pinMatched: Bool {
		return AccountController.shared.hasPinMatch(peerID)
	}
	
	public var pinned: Bool {
		return AccountController.shared.isPinned(self)
	}
	
	public var summary: String {
		let manager = PeeringController.shared.manager(for: peerID)
		var summary: String
		if age != nil {
			let format = NSLocalizedString("fullsummary", comment: "Text describing the peers age, gender, pin and verification status")
			summary = String(format: format, age!, gender.localizedRawValue, manager.verificationStatus)
		} else {
			let format = NSLocalizedString("smallsummary", comment: "Text describing the peers gender, pin and verification status")
			summary = String(format: format, gender.localizedRawValue, manager.verificationStatus)
		}
		if manager.unreadMessages > 0 { summary = "\(summary) - 📫 (\(manager.unreadMessages))" }
		return summary
	}
    
    var aggregateData: Data {
        get {
            let ageByte = UInt8(age ?? 0)
            let genderByte: GenderByte = gender == .queer ? .queer : gender == .female ? .female : .male;
            return Data([ageByte, genderByte.rawValue, UInt8(hasPicture), version])
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
                hasPicture = Bool(newValue[2])
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
        return PeerInfo(peerID: to, publicKey: publicKey, nickname: nickname, gender: gender, age: age, hasPicture: hasPicture)
    }
    
    init(peerID: PeerID, publicKey: AsymmetricPublicKey, nickname: String, gender: PeerInfo.Gender, age: Int?, hasPicture: Bool) {
        self.peerID = peerID
        self.publicKey = publicKey
        self.nickname = nickname
        self.gender = gender
        self.age = age
        self.hasPicture = hasPicture
    }
    
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
            hasPicture = Bool(aggregateData[2])
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

public struct Transcript {
	enum Direction {
		case send, receive
	}
	
	let direction: Direction
	let message: String
}
