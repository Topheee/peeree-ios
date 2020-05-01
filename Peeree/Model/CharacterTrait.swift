//
//  CharacterProperty.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

public struct CharacterTrait {
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
	
	static let standardTraits = [CharacterTrait(kind: .warmness), CharacterTrait(kind: .logicalConclusion), CharacterTrait(kind: .emotionalStability), CharacterTrait(kind: .dominance), CharacterTrait(kind: .vitality), CharacterTrait(kind: .ruleAwareness), CharacterTrait(kind: .socialCompetence), CharacterTrait(kind: .sensitiveness), CharacterTrait(kind: .vigilance), CharacterTrait(kind: .escapism), CharacterTrait(kind: .privateness), CharacterTrait(kind: .solicitousness), CharacterTrait(kind: .opennessToChange), CharacterTrait(kind: .frugalilty), CharacterTrait(kind: .perfectionism), CharacterTrait(kind: .strain)]
	
	enum Kind: String, CaseIterable {
		case warmness, logicalConclusion, emotionalStability, dominance, vitality, ruleAwareness, socialCompetence, sensitiveness, vigilance, escapism, privateness, solicitousness, opennessToChange, frugalilty, perfectionism, strain
		
		var kindDescription: String {
			return Bundle.main.localizedString(forKey: self.rawValue+"Description", value: NSLocalizedString("No description available.", comment: "For whatever reason there is no description available for this Character Trait."), table: nil)
		}
		
		/*
		 *  For genstrings
		 *
		 *  NSLocalizedString("warmness", comment: "Trait")
		 *  NSLocalizedString("logicalConclusion", comment: "Trait")
		 *  NSLocalizedString("emotionalStability", comment: "Trait")
		 *  NSLocalizedString("dominance", comment: "Trait")
		 *  NSLocalizedString("vitality", comment: "Trait")
		 *  NSLocalizedString("ruleAwareness", comment: "Trait")
		 *  NSLocalizedString("socialCompetence", comment: "Trait")
		 *  NSLocalizedString("sensitiveness", comment: "Trait")
		 *  NSLocalizedString("vigilance", comment: "Trait")
		 *  NSLocalizedString("escapism", comment: "Trait")
		 *  NSLocalizedString("privateness", comment: "Trait")
		 *  NSLocalizedString("solicitousness", comment: "Trait")
		 *  NSLocalizedString("opennessToChange", comment: "Trait")
		 *  NSLocalizedString("frugalilty", comment: "Trait")
		 *  NSLocalizedString("perfectionism", comment: "Trait")
		 *  NSLocalizedString("strain", comment: "Trait")
		 *
		 *  NSLocalizedString("warmnessDescription", comment: "TraitDescription")
		 *  NSLocalizedString("logicalConclusionDescription", comment: "TraitDescription")
		 *  NSLocalizedString("emotionalStabilityDescription", comment: "TraitDescription")
		 *  NSLocalizedString("dominanceDescription", comment: "TraitDescription")
		 *  NSLocalizedString("vitalityDescription", comment: "TraitDescription")
		 *  NSLocalizedString("ruleAwarenessDescription", comment: "TraitDescription")
		 *  NSLocalizedString("socialCompetenceDescription", comment: "TraitDescription")
		 *  NSLocalizedString("sensitivenessDescription", comment: "TraitDescription")
		 *  NSLocalizedString("vigilanceDescription", comment: "TraitDescription")
		 *  NSLocalizedString("escapismDescription", comment: "TraitDescription")
		 *  NSLocalizedString("privatenessDescription", comment: "TraitDescription")
		 *  NSLocalizedString("solicitousnessDescription", comment: "TraitDescription")
		 *  NSLocalizedString("opennessToChangeDescription", comment: "TraitDescription")
		 *  NSLocalizedString("frugaliltyDescription", comment: "TraitDescription")
		 *  NSLocalizedString("perfectionismDescription", comment: "TraitDescription")
		 *  NSLocalizedString("strainDescription", comment: "TraitDescription")
		 */
	}
	
	enum ApplyType: String, CaseIterable {
		case yes, no, moreOrLess, dontKnow
		
		/*
		 *  For genstrings
		 *
		 *  NSLocalizedString("yes", comment: "The character trait describes the user well")
		 *  NSLocalizedString("no", comment: "The character trait is not representative for the user")
		 *  NSLocalizedString("moreOrLess", comment: "The character trait describes the user partially")
		 *  NSLocalizedString("dontKnow", comment: "The user is not sure whether the character trait describes him or her")
		 */
	}
	
	let kind: Kind
	// does this trait apply to the peer?
	var applies: ApplyType = .dontKnow
	
	init(kind: Kind) {
		self.kind = kind
	}
	
	init(kind: Kind, applies: ApplyType) {
		self.kind = kind
		self.applies = applies
	}
}

class CharacterTraitCoding: NSObject, NSSecureCoding {
	private static let ApplKey = "applies"
	private static let KindKey = "trait"
	
	@objc static var supportsSecureCoding : Bool {
		return true
	}
	
	static func codingArray(_ structArray: [CharacterTrait]) -> [CharacterTraitCoding] {
		var ret: [CharacterTraitCoding] = []
		for trait in structArray {
			ret.append(CharacterTraitCoding(characterTrait: trait))
		}
		return ret
	}
	
	static func structArray(_ codingArray: [CharacterTraitCoding]) -> [CharacterTrait] {
		var ret: [CharacterTrait] = []
		for trait in codingArray {
			ret.append(trait.characterTrait)
		}
		return ret
	}
	
	var characterTrait: CharacterTrait
	
	required init(characterTrait: CharacterTrait) {
		self.characterTrait = characterTrait
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		guard let rawKindValue = aDecoder.decodeObject(of: NSString.self, forKey: CharacterTraitCoding.KindKey) else { return nil }
		guard let decodedKind = CharacterTrait.Kind(rawValue:rawKindValue as String) else { return nil }
		
		var applies: CharacterTrait.ApplyType = .dontKnow
		if let rawAppliesValue = aDecoder.decodeObject(of: NSString.self, forKey: CharacterTraitCoding.ApplKey) {
			applies = CharacterTrait.ApplyType(rawValue:rawAppliesValue as String) ?? CharacterTrait.ApplyType.dontKnow
		}
		
		characterTrait = CharacterTrait(kind: decodedKind, applies: applies)
	}
	
	@objc func encode(with aCoder: NSCoder) {
		aCoder.encode(characterTrait.applies.rawValue, forKey: CharacterTraitCoding.ApplKey)
		aCoder.encode(characterTrait.kind.rawValue, forKey: CharacterTraitCoding.KindKey)
	}
}
