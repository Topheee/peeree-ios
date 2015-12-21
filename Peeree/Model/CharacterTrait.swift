//
//  CharacterProperty.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

class CharacterTrait: NSObject, NSSecureCoding {
	enum ApplyType: Int {
		case No = 0, Yes, MoreOrLess, DontKnow
	}
	
	private static let ApplKey = "applies"
	private static let DescKey = "description"
	private static let NameKey = "name"
	
	@objc static func supportsSecureCoding() -> Bool {
		return true
	}
	
	// TODO localization
	internal static let ApplyTypeNames = ["no", "yes", "more or less", "don't know"]
	
	// does this trait apply to the peer?
	var applies: ApplyType
	// what is this trait about?
	var traitDescription: String
	var name: String
	
	@objc required init(name: String, description: String) {
		applies = .DontKnow
		self.traitDescription = description
		self.name = name
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		applies = ApplyType(rawValue: aDecoder.decodeIntegerForKey(CharacterTrait.ApplKey))!
		traitDescription = aDecoder.decodeObjectForKey(CharacterTrait.DescKey) as! String
		name = aDecoder.decodeObjectForKey(CharacterTrait.NameKey) as! String
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeInteger(applies.rawValue, forKey: CharacterTrait.ApplKey)
		aCoder.encodeObject(description, forKey: CharacterTrait.DescKey)
		aCoder.encodeObject(name, forKey: CharacterTrait.NameKey)
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