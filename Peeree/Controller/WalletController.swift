//
//  WalletController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 11.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import UIKit
import StoreKit

/*
0. WalletController registers itself as observer for app store notifications
1. ShopController requests pin point offerings
2. ShopController receives pin point offerings
3. ShopViewController shows offerings
4. User picks offering
5. ShopController makes payment request at App Store
6. App Store calls WalletController, that product will be delivered
7. App Store delivers product
8. WalletController increments the amount of pin points and notifies the current view controller about it
 */

/*
*	The WalletController maintains the bought pin points of the user and, in future releases, the already bought premium features, as well as enabling them on the user's demand.
*	It also is informed by the in-app purchase server, when a new purchase was done.
*	And finally, every local action, that reduces the amount of the bought pin points, including transfering them to a remote p2p device with the same Apple ID, has to be requested and granted through this class.
*/
final class WalletController {
	/* Never change this value after the first app store release! */
	static let pinCost = 10
	
	private static var _availablePinPoints = 200
    static var availablePinPoints: Int {
		return _availablePinPoints
	}
	
    static func requestPin(successfullCallback: () -> Void) {
        let title = NSLocalizedString("Spend pin points", comment: "Title of the alert which pops up when the user is about to spend in-app currency.")
        var message: String
        var actions: [UIAlertAction] = [UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .Cancel, handler: nil)]
        
		if _availablePinPoints > pinCost {
            message = NSLocalizedString("You have %d pin points available.", comment: "Alert message if the user is about to spend in-app currency and has enough of it in his pocket.")
            message = String(format: message, WalletController._availablePinPoints)
            let title = String(format: NSLocalizedString("Spend %d of them", comment: "The user accepts to spend pin points for this action."), WalletController.pinCost)
            actions.append(UIAlertAction(title: title, style: .Default) { action in
                _availablePinPoints -= pinCost
                successfullCallback()
            })
        } else {
            message = NSLocalizedString("You do not have enough pin points available.", comment: "Alert message if the user is about to buy something and has not enough of in-app money in his pocket.")
        }
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .ActionSheet)
        for action in actions {
            alertController.addAction(action)
        }
        alertController.present(nil)
	}
	
	static func increasePinPoints(by: Int) {
		_availablePinPoints += by
	}
    
    static func getCurrentOfferings() -> (points: Int, price: NSDecimalNumber) {
        return (10, NSDecimalNumber(integer: 1))
    }
}