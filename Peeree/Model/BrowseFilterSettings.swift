//
//  BrowseFilterSettings.swift
//  Peeree
//
//  Created by Christopher Kobusch on 13.09.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

class BrowseFilterSettings: NSObject, NSCoding {
	
	static private let kPrefKey = "peeree-prefs-browse-filter"
	
	static var sharedSettings: BrowseFilterSettings {
		return unarchiveObjectFromUserDefs(kPrefKey) ?? BrowseFilterSettings()
	}
	
	enum GenderType: Int {
		case Unspecified = 0, Male, Female
	}
	
	private static let kAgeMinKey = "ageMin"
	private static let kAgeMaxKey = "ageMax"
	private static let kGenderKey = "gender"
	
	//range from 10..100
	var ageMin: Float = 10.0
	//range from 10..100 or 0, where 0 means ∞
	var ageMax: Float = 0.0
	
	var gender: GenderType = .Unspecified
	
	override init() {
		
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		gender = GenderType(rawValue: aDecoder.decodeIntegerForKey(BrowseFilterSettings.kGenderKey))!
		ageMin = aDecoder.decodeFloatForKey(BrowseFilterSettings.kAgeMinKey)
		ageMax = aDecoder.decodeFloatForKey(BrowseFilterSettings.kAgeMaxKey)
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeFloat(ageMin, forKey: BrowseFilterSettings.kAgeMinKey)
		aCoder.encodeFloat(ageMax, forKey: BrowseFilterSettings.kAgeMaxKey)
		aCoder.encodeInteger(gender.rawValue, forKey: BrowseFilterSettings.kGenderKey)
	}
	
	func writeToDefaults() {
		archiveObjectInUserDefs(self, forKey: BrowseFilterSettings.kPrefKey)
	}
}