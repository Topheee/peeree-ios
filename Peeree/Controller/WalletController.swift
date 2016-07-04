//
//  WalletController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 11.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import Foundation

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
	
	private static var availablePinPoints = 0
	
	static func getAvailablePinPoints() -> Int {
		return availablePinPoints
	}
	
	static func requestPin() -> Bool {
		if availablePinPoints > pinCost {
			availablePinPoints -= pinCost
			return true
		}
		return false
	}
	
	static func increasePinPoints(by: Int) {
		availablePinPoints += by
	}
}