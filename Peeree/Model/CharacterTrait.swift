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
	
	private static let applKey = "applies"
	private static let descKey = "description"
	private static let nameKey = "name"
	
	// TODO remove this internal static let kPrefDictKey = "peeree-prefs-char-traits"
	
	// TODO localization
	internal static let applyTypeNames = ["no", "yes", "more or less", "don't know"]
	
	// does this trait apply to the peer?
	var applies: ApplyType
	// what is this trait about?
	var description: String
	var name: String
	
	init(name: String, description: String) {
		applies = .DontKnow
		self.description = description
		self.name = name
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		applies = ApplyType(rawValue: aDecoder.decodeIntegerForKey(CharacterTrait.applKey))!
		description = aDecoder.decodeObjectForKey(CharacterTrait.descKey) as! String
		name = aDecoder.decodeObjectForKey(CharacterTrait.nameKey) as! String
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeInteger(applies.rawValue, forKey: CharacterTrait.applKey)
		aCoder.encodeObject(description, forKey: CharacterTrait.descKey)
		aCoder.encodeObject(name, forKey: CharacterTrait.nameKey)
	}
	
	static func standardTraits() -> Array<CharacterTrait> {
		// TODO localization
		return [CharacterTrait(name: "warmness", description: ""),
			CharacterTrait(name: "emotional stability", description: ""),
			CharacterTrait(name: "dominance", description: ""),
			CharacterTrait(name: "vitality", description: ""),
			CharacterTrait(name: "rule awareness", description: ""),
			CharacterTrait(name: "social competence", description: ""),
			CharacterTrait(name: "sensitiveness", description: ""),
			CharacterTrait(name: "vigilance", description: ""),
			CharacterTrait(name: "escapism", description: ""),
			CharacterTrait(name: "privateness", description: ""),
			CharacterTrait(name: "solicitousness", description: ""),
			CharacterTrait(name: "openness to change", description: ""),
			CharacterTrait(name: "frugalilty", description: ""),
			CharacterTrait(name: "perfectionism", description: "If 'partial ok' is nothing you are satisfied with, this applies to you."),
			CharacterTrait(name: "strain", description: "")]
	}
}