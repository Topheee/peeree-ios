//
//  PeereePurchasement.swift
//  Peeree
//
//  Created by Christopher Kobusch on 04.11.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import Foundation
import UIKit.UIImage
import PassKit.PKPaymentRequest // TODO import StoreKit instead of this

class PeereeOffering: NSSecureCoding {
	private static let durKey = "minutesDuration"
	private static let durKey = "minutesDuration"
	private static let durKey = "minutesDuration"
	private static let durKey = "minutesDuration"
	private static let durKey = "minutesDuration"
	
	/*	Each Purchasement type has a unique representation in the PeereePurchasementTypes enum.
	 *	The rawType of that representation is stored in this Int. If there is no matching PeereePurchasementTypes for this identifier, the version of this app may be to low to support this purchasement.
	 */
	var identifier: Int
	var shortDescription: String
	var longDescription: String
	var costs: PKPaymentRequest
	var icon: UIImage
	var expirationDate: NSDate
	
	
	@objc static func supportsSecureCoding() -> Bool {
		return true
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		// TODO empty stub
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		// TODO decode the rest of the properties
		aDecoder.decodeObjectOfClass(PKPaymentRequest.self, forKey: <#T##String#>)
	}
}

class PinPointOffering: PeereeOffering {
	private static let pinPointsKey = "purchasedPinPoints"
	
	var purchasedPinPoints: Int
	
	@objc override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		
		aCoder.encodeInteger(purchasedPinPoints, forKey: PinPointOffering.pinPointsKey)
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		purchasedPinPoints = aDecoder.decodeIntegerForKey(PinPointOffering.pinPointsKey)
		super.init(coder: aDecoder)
	}
}

// TODO managing local activation and expiering of a premium feature
class PremiumFeatureOffering: PeereeOffering {
	private static let durKey = "minutesDuration"
	
	var minutesDuration: Int
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		
		aCoder.encodeInteger(minutesDuration, forKey: PremiumFeatureOffering.durKey)
	}
	
	required init?(coder aDecoder: NSCoder) {
		minutesDuration = aDecoder.decodeIntegerForKey(PremiumFeatureOffering.durKey)
		super.init(coder: aDecoder)
	}
}

enum PeereeOfferingTypes: Int {
	case PINPOINTS
	// TODO premium features
}