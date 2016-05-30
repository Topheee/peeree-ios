//
//  BrowseFilterSettings.swift
//  Peeree
//
//  Created by Christopher Kobusch on 13.09.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

// TODO change to observed things like UserPeerInfo
class BrowseFilterSettings: NSObject, NSCoding {
	
	private static let PrefKey = "peeree-prefs-browse-filter"
	
	private static let AgeMinKey = "ageMin"
	private static let AgeMaxKey = "ageMax"
	private static let GenderKey = "gender"
	
	static var sharedSettings: BrowseFilterSettings {
		return unarchiveObjectFromUserDefs(PrefKey) ?? BrowseFilterSettings()
	}
	
	enum GenderType: Int {
		case Unspecified = 0, Male, Female
	}
	
	//range from 10..100
	var ageMin: Float = 10.0
	//range from 10..100 or 0, where 0 means ∞
	var ageMax: Float = 0.0
	
	var gender: GenderType = .Unspecified
	
	override init() {
		
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		gender = GenderType(rawValue: aDecoder.decodeIntegerForKey(BrowseFilterSettings.GenderKey))!
		ageMin = aDecoder.decodeFloatForKey(BrowseFilterSettings.AgeMinKey)
		ageMax = aDecoder.decodeFloatForKey(BrowseFilterSettings.AgeMaxKey)
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeFloat(ageMin, forKey: BrowseFilterSettings.AgeMinKey)
		aCoder.encodeFloat(ageMax, forKey: BrowseFilterSettings.AgeMaxKey)
		aCoder.encodeInteger(gender.rawValue, forKey: BrowseFilterSettings.GenderKey)
	}
	
	func writeToDefaults() {
		archiveObjectInUserDefs(self, forKey: BrowseFilterSettings.PrefKey)
	}
	
	func checkPeer(peer: SerializablePeerInfo) -> Bool {
		let matchingGender = gender == .Unspecified || (gender == .Female && peer.hasVagina)
		let matchingAge = ageMin <= Float(peer.age) && (ageMax == 0.0 || ageMax >= Float(peer.age))
		
		return matchingAge && matchingGender
	}
}