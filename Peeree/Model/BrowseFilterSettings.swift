//
//  BrowseFilterSettings.swift
//  Peeree
//
//  Created by Christopher Kobusch on 13.09.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

/**
 *  This class encapsulates all values with which the remote peers are filtered before they are presented to the user.
 *  Except for the Singleton it is NOT thread-safe, and as there is currently only one writing entity there is no need to implement this.ssss
 */
final class BrowseFilterSettings: NSObject, NSSecureCoding {
	private static let PrefKey = "peeree-prefs-browse-filter"
	
	private static let AgeMinKey = "ageMin"
    private static let AgeMaxKey = "ageMax"
    private static let GenderKey = "gender"
    private static let OnlyWithAgeKey = "WithAgeKey"
    private static let OnlyWithPictureKey = "WithPictureKey"
	
	static var sharedSettings: BrowseFilterSettings {
        struct Singleton {
            static var sharedInstance: BrowseFilterSettings!
            static var token: dispatch_once_t = 0
        }
        dispatch_once(&Singleton.token, { () -> Void in
            Singleton.sharedInstance = unarchiveObjectFromUserDefs(PrefKey) ?? BrowseFilterSettings()
        })
        
		return Singleton.sharedInstance
	}
    
    static func supportsSecureCoding() -> Bool {
        return true
    }
	
	enum GenderType: Int {
		case Unspecified = 0, Male, Female, Queer
	}
	
	/// range from 10..100
	var ageMin: Float = 10.0
	/// range from 10..100 or 0, where 0 means ∞
	var ageMax: Float = 0.0
	
	var gender: GenderType = .Unspecified
    
    var onlyWithAge: Bool = false
    var onlyWithPicture: Bool = false
	
	private override init() {}
	
	@objc required init?(coder aDecoder: NSCoder) {
		gender = GenderType(rawValue: aDecoder.decodeIntegerForKey(BrowseFilterSettings.GenderKey))!
        ageMin = aDecoder.decodeFloatForKey(BrowseFilterSettings.AgeMinKey)
        ageMax = aDecoder.decodeFloatForKey(BrowseFilterSettings.AgeMaxKey)
        onlyWithAge = aDecoder.decodeBoolForKey(BrowseFilterSettings.OnlyWithAgeKey)
        onlyWithPicture = aDecoder.decodeBoolForKey(BrowseFilterSettings.OnlyWithPictureKey)
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeFloat(ageMin, forKey: BrowseFilterSettings.AgeMinKey)
        aCoder.encodeFloat(ageMax, forKey: BrowseFilterSettings.AgeMaxKey)
        aCoder.encodeInteger(gender.rawValue, forKey: BrowseFilterSettings.GenderKey)
        aCoder.encodeBool(onlyWithAge, forKey: BrowseFilterSettings.OnlyWithAgeKey)
        aCoder.encodeBool(onlyWithPicture, forKey: BrowseFilterSettings.OnlyWithPictureKey)
	}
	
	func writeToDefaults() {
		archiveObjectInUserDefs(self, forKey: BrowseFilterSettings.PrefKey)
	}
	
	func checkPeer(peer: PeerInfo) -> Bool {
		let matchingGender = gender == .Unspecified || (gender == .Female && peer.gender == .Female) || (gender == .Male && peer.gender == .Male)
        var matchingAge: Bool
        if let peerAge = peer.age {
            matchingAge = ageMin <= Float(peerAge) && (ageMax == 0.0 || ageMax >= Float(peerAge))
        } else {
            matchingAge = true
        }
        let hasRequiredProperties = (!onlyWithPicture || peer.hasPicture) && (!onlyWithAge || peer.age != nil)
		
		return matchingAge && matchingGender && hasRequiredProperties
	}
}