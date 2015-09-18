//
//  CharacterProperty.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

class CharacterTrait: NSCoding {
	enum ApplyType: Int {
		case No = 0, Yes, MoreOrLess, DontKnow
	}
	//does this trait apply to the peer?
	var applies: ApplyType
	
	private static let appliesKey = "appliesKey"
	
	@objc required init?(coder aDecoder: NSCoder) {
		applies = ApplyType(rawValue: aDecoder.decodeIntegerForKey(CharacterTrait.appliesKey))!
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeInteger(applies.rawValue, forKey: CharacterTrait.appliesKey)
	}
}