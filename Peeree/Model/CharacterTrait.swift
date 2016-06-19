//
//  CharacterProperty.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

class CharacterTrait: NSObject, NSSecureCoding {
	enum ApplyType: String {
		case Applies, AppliesNot, AppliesMoreOrLess, DontKnow
        
        static let values = [Applies, AppliesNot, AppliesMoreOrLess, DontKnow]
        
            // TODO write the value into strings file
        /*
         *  For genstrings
         *
         *  yes: NSLocalizedString("Applies", comment: "The character trait describes the user well")
         *  no: NSLocalizedString("AppliesNot", comment: "The character trait is not representative for the user")
         *  more or less: NSLocalizedString("AppliesMoreOrLess", comment: "The character trait describes the user partially")
         *  don't know: NSLocalizedString("DontKnow", comment: "The user is not sure whether the character trait describes him or her")
        */
	}
	
	private static let ApplKey = "applies"
	private static let DescKey = "description"
	private static let NameKey = "name"
	
	@objc static func supportsSecureCoding() -> Bool {
		return true
	}
	
	// does this trait apply to the peer?
	var applies: ApplyType = .DontKnow
	// what is this trait about?
	let traitDescription: String
	let name: String
	
	@objc required init(name: String, description: String) {
		self.traitDescription = description
		self.name = name
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
        if let rawAppliesValue = aDecoder.decodeObjectOfClass(NSString.self, forKey: CharacterTrait.ApplKey) as? String {
            applies = ApplyType(rawValue:rawAppliesValue) ?? ApplyType.DontKnow
        } else {
            assertionFailure()
        }
		traitDescription = aDecoder.decodeObjectForKey(CharacterTrait.DescKey) as! String
        name = aDecoder.decodeObjectOfClass(NSString.self, forKey: CharacterTrait.NameKey) as! String
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(applies.rawValue, forKey: CharacterTrait.ApplKey)
		aCoder.encodeObject(traitDescription, forKey: CharacterTrait.DescKey)
		aCoder.encodeObject(name, forKey: CharacterTrait.NameKey)
	}
	
	static func standardTraits() -> [CharacterTrait] {
		// TODO localization and transform to static property if possible
        
        /* From wikipedia
         Wärme (z. B. Wohlfühlen in Gesellschaft)
         logisches Schlussfolgern
         emotionale Stabilität
         Dominanz
         Lebhaftigkeit
         Regelbewusstsein (z. B. Moral)
         soziale Kompetenz (z. B. Kontaktfreude)
         Empfindsamkeit
         Wachsamkeit (z. B. Misstrauen)
         Abgehobenheit (z. B. Realitätsnähe)
         Privatheit
         Besorgtheit
         Offenheit für Veränderungen
         Selbstgenügsamkeit
         Perfektionismus
         Anspannung
         */
        return [CharacterTrait(name: "warmness", description: ""),
                CharacterTrait(name: "logical conclusion", description: ""),
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
                CharacterTrait(name: "perfectionism", description: "If 'partially ok' is nothing you are satisfied with, this applies to you."),
                CharacterTrait(name: "strain", description: "")]
	}
}