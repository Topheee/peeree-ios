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
		case Yes, No, MoreOrLess, DontKnow
        
        static let values = [Yes, No, MoreOrLess, DontKnow]
        
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
    static let standardTraits: [CharacterTrait] = [
        CharacterTrait(name: NSLocalizedString("Warmness", comment: "Trait"),
            description: NSLocalizedString("How good are you to other people and feel in company?", comment: "Warmness")),
        CharacterTrait(name: NSLocalizedString("Logical Conclusion", comment: "Trait"),
            description: NSLocalizedString("Are you always acting rational?", comment: "Logical Conclusion")),
        CharacterTrait(name: NSLocalizedString("Emotional Stability", comment: "Trait"),
            description: NSLocalizedString("How much can you stand emotional hard feelings?", comment: "Emotional Stability")),
        CharacterTrait(name: NSLocalizedString("Dominance", comment: "Trait"),
            description: NSLocalizedString("Do others follow your instructions?", comment: "Dominance")),
        CharacterTrait(name: NSLocalizedString("Vitality", comment: "Trait"),
            description: NSLocalizedString("Are you feeling vivid and full of energy?", comment: "Vitality")),
        CharacterTrait(name: NSLocalizedString("Rule awareness", comment: "Trait"),
            description: NSLocalizedString("Are you a good citizen?", comment: "Rule awareness")),
        CharacterTrait(name: NSLocalizedString("Social Competence", comment: "Trait"),
            description: NSLocalizedString("How well can you deal with different personalities?", comment: "Social Competence")),
        CharacterTrait(name: NSLocalizedString("Sensitiveness", comment: "Trait"),
            description: NSLocalizedString("How intense do you react to incidents affecting you?", comment: "Sensitiveness")),
        CharacterTrait(name: NSLocalizedString("Vigilance", comment: "Trait"),
            description: NSLocalizedString("Don't you trust other people?", comment: "Vigilance")),
        CharacterTrait(name: NSLocalizedString("Escapism", comment: "Trait"),
            description: NSLocalizedString("Do you feel far away from any reality?", comment: "Escapism")),
        CharacterTrait(name: NSLocalizedString("Privateness", comment: "Trait"),
            description: NSLocalizedString("Do you avoid sharing your secrets and embarrassments?", comment: "Privateness")),
        CharacterTrait(name: NSLocalizedString("Solicitousness", comment: "Trait"),
            description: NSLocalizedString("Are you often afraid of anything?", comment: "Solicitousness")),
        CharacterTrait(name: NSLocalizedString("Openness to Change", comment: "Trait"),
            description: NSLocalizedString("Are new environments not a big deal for you?", comment: "Openness to Change")),
        CharacterTrait(name: NSLocalizedString("Frugalilty", comment: "Trait"),
            description: NSLocalizedString("Do you feel happy with few things properly set up in your live?", comment: "Frugalilty")),
        CharacterTrait(name: NSLocalizedString("Perfectionism", comment: "Trait"),
            description: NSLocalizedString("Is 'partially ok' nothing you are satisfied with?", comment: "Perfectionism")),
        CharacterTrait(name: NSLocalizedString("Strain", comment: "Trait"),
            description: NSLocalizedString("Are you always aware of everything around you?", comment: "Strain"))
        ]
}