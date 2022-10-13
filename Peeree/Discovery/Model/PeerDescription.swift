//
//  PeerDescription.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

/// The JPEG compression quality when serializing portraits.
let StandardPortraitCompressionQuality: CGFloat = 0.0

/// The Peeree identity of a user combined with their mandatory info.
public struct Peer: Codable, Equatable {
	// MARK: - Public and Internal

	/// Constructs a `Peer` with its properties.
	public init(id: PeereeIdentity, info: PeerInfo) {
		self.id = id
		self.info = info
	}

	/// Constructs a `Peer` from its dismantled properties.
	public init(peerID: PeerID, publicKey: AsymmetricPublicKey, nickname: String, gender: PeerInfo.Gender, age: Int?, hasPicture: Bool) {
		self.init(id: PeereeIdentity(peerID: peerID, publicKey: publicKey),
				  info: PeerInfo(nickname: nickname, gender: gender, age: age, hasPicture: hasPicture))
	}

	/// Constructs a `Peer` from the binary representations of its properties.
	init?(peerID: PeerID, publicKeyData: Data, aggregateData: Data, nicknameData: Data) {
		guard let id = try? PeereeIdentity(peerID: peerID, publicKeyData: publicKeyData),
			  let pi = PeerInfo(aggregateData: aggregateData, nicknameData: nicknameData) else {
			return nil
		}

		self.id = id
		info = pi
	}

	/// Constructs a `Peer` from the binary representations of its properties and the components of its `id`.
	init?(peerID: PeerID, publicKey: AsymmetricPublicKey, aggregateData: Data, nicknameData: Data) {
		id = PeereeIdentity(peerID: peerID, publicKey: publicKey)
		if let i = PeerInfo(aggregateData: aggregateData, nicknameData: nicknameData) {
			info = i
		} else {
			return nil
		}
	}

	// MARK: Constants

	/// The PeereeIdentity of this peer.
	public let id: PeereeIdentity

	// MARK: Variables

	/// The basic properties of a peer.
	public var info: PeerInfo
}

public func ==(lhs: Peer, rhs: Peer) -> Bool {
	return lhs.id.peerID == rhs.id.peerID
}

func ==(lhs: Peer, rhs: PeerID) -> Bool {
	return lhs.id.peerID == rhs
}

func ==(lhs: PeerID, rhs: Peer) -> Bool {
	return lhs == rhs.id.peerID
}

/**
  Adds conformance to the `Hashable` protocol for `Peer`, based on its `peerID`.

  Attention: We consider all Peers with the same PeereeID equal, regardless of the public key!
 */
extension Peer: Hashable {
	/**
	 Computes the hash of the `Peer` based on its `peerID`.

	  - Attention: We consider all Peers with the same PeereeID equal, regardless of the public key!
	 */
	public var hashValue: Int { return id.peerID.hashValue }

	/**
	 Computes the hash of the `Peer` based on its `peerID`.

	  - Attention: We consider all Peers with the same PeereeID equal, regardless of the public key!
	 */
	public func hash(into hasher: inout Hasher) { id.peerID.hash(into: &hasher) }
}

/// All information a user may give about themselves.
public struct PeerInfo: Codable {
	// MARK: - Public and Internal

	/// Constructs a `PeerInfo` from its parts.
	public init(nickname: String, gender: PeerInfo.Gender, age: Int?, hasPicture: Bool) {
		self.nickname = nickname
		self.gender = gender
		self.age = age
		self.hasPicture = hasPicture
	}

	/// Constructs a `PeerInfo` from the binary representation of its parts.
	init?(aggregateData: Data, nicknameData: Data) {
		guard aggregateData.count > 2 else { return nil }
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
	}

	// MARK: Classes, Structs, Enums

	/// The available genders in the UI.
	public enum Gender: String, CaseIterable, Codable {
		case male, female, queer

		/*
		 *  For genstrings
		 *
		 *  NSLocalizedString("male", comment: "Male gender.")
		 *  NSLocalizedString("female", comment: "Female gender.")
		 *  NSLocalizedString("queer", comment: "Gender type for everyone who does not fit into the other two genders.")
		 */
	}

	/// The binary representation of a gender.
	private enum GenderByte: UInt8 {
		case male, female, queer
	}

	// MARK: Static Constants

	/// UI caps for age values.
	public static let MinAge = 18, MaxAge = 80
	/// PostgreSQL can store strings up to this length very efficiently
	public static let MaxEmailSize = 126
	/// 1 non-extended BLE packet length would be 27. Since most devices seem to support extended packets, we chose something higher and cap it on the phy level
	public static let MaxNicknameSize = 184
	
//	public struct AuthenticationStatus: OptionSet {
//		public let rawValue: Int
//
//		/// we authenticated ourself to the peer
//		public static let to	= AuthenticationStatus(rawValue: 1 << 0)
//		/// the peer authenticated himself to us
//		public static let from  = AuthenticationStatus(rawValue: 1 << 1)
//
//		public static let full: AuthenticationStatus = [.to, .from]
//
//		public init(rawValue: Int) {
//			self.rawValue = rawValue
//		}
//	}

//	var authenticationStatus: AuthenticationStatus = []

	// MARK: Variables
	
	public var nickname = ""

	public var gender = Gender.queer
	public var age: Int? = nil

	/**
	 *	Version information with the same format as Apple's dylib version format. This is used to test the compatibility of two Peeree apps exchanging data via bluetooth.
	 */
	public var version = UInt8(0)
	
	public var lastChanged = Date.distantPast
	
	public var hasPicture: Bool = false

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

	var lastChangedData: Data {
		get {
			var changed = lastChanged.timeIntervalSince1970
			return Data(bytes: &changed, count: MemoryLayout<TimeInterval>.size)
		}
		set {
			guard newValue.count >= MemoryLayout<TimeInterval>.size else { return }
			
			var changed: TimeInterval = 0.0
			withUnsafeMutableBytes(of: &changed) { pointer in
				pointer.copyBytes(from: newValue.subdata(in: 0..<MemoryLayout<TimeInterval>.size))
			}
			lastChanged = Date(timeIntervalSince1970: changed)
		}
	}
}
