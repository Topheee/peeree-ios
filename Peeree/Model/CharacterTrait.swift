//
//  CharacterProperty.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

struct CharacterTrait {
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
    
    static let standardTraits = [CharacterTrait(kind: .Warmness), CharacterTrait(kind: .LogicalConclusion), CharacterTrait(kind: .EmotionalStability), CharacterTrait(kind: .Dominance), CharacterTrait(kind: .Vitality), CharacterTrait(kind: .RuleAwareness), CharacterTrait(kind: .SocialCompetence), CharacterTrait(kind: .Sensitiveness), CharacterTrait(kind: .Vigilance), CharacterTrait(kind: .Escapism), CharacterTrait(kind: .Privateness), CharacterTrait(kind: .Solicitousness), CharacterTrait(kind: .OpennessToChange), CharacterTrait(kind: .Frugalilty), CharacterTrait(kind: .Perfectionism), CharacterTrait(kind: .Strain)]
    
    enum Kind: String {
        case Warmness, LogicalConclusion, EmotionalStability, Dominance, Vitality, RuleAwareness, SocialCompetence, Sensitiveness, Vigilance, Escapism, Privateness, Solicitousness, OpennessToChange, Frugalilty, Perfectionism, Strain
        
        static let values = [Warmness, LogicalConclusion, EmotionalStability, Dominance, Vitality, RuleAwareness, SocialCompetence, Sensitiveness, Vigilance, Escapism, Privateness, Solicitousness, OpennessToChange, Frugalilty, Perfectionism, Strain]
        
        var kindDescription: String {
            return Bundle.main.localizedString(forKey: self.rawValue+"Description", value: NSLocalizedString("No description available.", comment: "For whatever reason there is no description available for this Character Trait."), table: nil)
        }
        
        /*
         *  For genstrings
         *
         *  NSLocalizedString("Warmness", comment: "Trait")
         *  NSLocalizedString("LogicalConclusion", comment: "Trait")
         *  NSLocalizedString("EmotionalStability", comment: "Trait")
         *  NSLocalizedString("Dominance", comment: "Trait")
         *  NSLocalizedString("Vitality", comment: "Trait")
         *  NSLocalizedString("RuleAwareness", comment: "Trait")
         *  NSLocalizedString("SocialCompetence", comment: "Trait")
         *  NSLocalizedString("Sensitiveness", comment: "Trait")
         *  NSLocalizedString("Vigilance", comment: "Trait")
         *  NSLocalizedString("Escapism", comment: "Trait")
         *  NSLocalizedString("Privateness", comment: "Trait")
         *  NSLocalizedString("Solicitousness", comment: "Trait")
         *  NSLocalizedString("OpennessToChange", comment: "Trait")
         *  NSLocalizedString("Frugalilty", comment: "Trait")
         *  NSLocalizedString("Perfectionism", comment: "Trait")
         *  NSLocalizedString("Strain", comment: "Trait")
         *
         *  NSLocalizedString("WarmnessDescription", comment: "TraitDescription")
         *  NSLocalizedString("LogicalConclusionDescription", comment: "TraitDescription")
         *  NSLocalizedString("EmotionalStabilityDescription", comment: "TraitDescription")
         *  NSLocalizedString("DominanceDescription", comment: "TraitDescription")
         *  NSLocalizedString("VitalityDescription", comment: "TraitDescription")
         *  NSLocalizedString("RuleAwarenessDescription", comment: "TraitDescription")
         *  NSLocalizedString("SocialCompetenceDescription", comment: "TraitDescription")
         *  NSLocalizedString("SensitivenessDescription", comment: "TraitDescription")
         *  NSLocalizedString("VigilanceDescription", comment: "TraitDescription")
         *  NSLocalizedString("EscapismDescription", comment: "TraitDescription")
         *  NSLocalizedString("PrivatenessDescription", comment: "TraitDescription")
         *  NSLocalizedString("SolicitousnessDescription", comment: "TraitDescription")
         *  NSLocalizedString("OpennessToChangeDescription", comment: "TraitDescription")
         *  NSLocalizedString("FrugaliltyDescription", comment: "TraitDescription")
         *  NSLocalizedString("PerfectionismDescription", comment: "TraitDescription")
         *  NSLocalizedString("StrainDescription", comment: "TraitDescription")
         */
    }
    
    enum ApplyType: String {
        case Yes, No, MoreOrLess, DontKnow
        
        static let values = [Yes, No, MoreOrLess, DontKnow]
        
        /*
         *  For genstrings
         *
         *  NSLocalizedString("Yes", comment: "The character trait describes the user well")
         *  NSLocalizedString("No", comment: "The character trait is not representative for the user")
         *  NSLocalizedString("MoreOrLess", comment: "The character trait describes the user partially")
         *  NSLocalizedString("DontKnow", comment: "The user is not sure whether the character trait describes him or her")
         */
    }
    
    let kind: Kind
    // does this trait apply to the peer?
    var applies: ApplyType = .DontKnow
    
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
//        var i = 0
//        return [CharacterTraitCoding](count: structArray.count, repeatedValue: CharacterTraitCoding(characterTrait: structArray[i++]))
        var ret: [CharacterTraitCoding] = []
        for trait in structArray {
            ret.append(CharacterTraitCoding(characterTrait: trait))
        }
        return ret
    }
    
    static func structArray(_ codingArray: [CharacterTraitCoding]) -> [CharacterTrait] {
//        var i = 0
//        return [CharacterTrait](count: codingArray.count, repeatedValue: codingArray[i++].characterTrait)
        var ret: [CharacterTrait] = []
        for trait in codingArray {
            ret.append(trait.characterTrait)
        }
        return ret
    }
	
	// does this trait apply to the peer?
    var characterTrait: CharacterTrait
	
	required init(characterTrait: CharacterTrait) {
		self.characterTrait = characterTrait
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
        guard let rawKindValue = aDecoder.decodeObject(of: NSString.self, forKey: CharacterTraitCoding.KindKey) as? String else { return nil }
        guard let decodedKind = CharacterTrait.Kind(rawValue:rawKindValue) else { return nil }
        
        var applies: CharacterTrait.ApplyType = .DontKnow
        if let rawAppliesValue = aDecoder.decodeObject(of: NSString.self, forKey: CharacterTraitCoding.ApplKey) as? String {
            applies = CharacterTrait.ApplyType(rawValue:rawAppliesValue) ?? CharacterTrait.ApplyType.DontKnow
        }
        
        characterTrait = CharacterTrait(kind: decodedKind, applies: applies)
	}
	
	@objc func encode(with aCoder: NSCoder) {
		aCoder.encode(characterTrait.applies.rawValue, forKey: CharacterTraitCoding.ApplKey)
		aCoder.encode(characterTrait.kind.rawValue, forKey: CharacterTraitCoding.KindKey)
	}
}
