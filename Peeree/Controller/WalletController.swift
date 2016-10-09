//
//  WalletController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 11.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import UIKit

// Maybe store Transaction Receipt instead of simple value in User Defaults to prevent Users from tampering with that value:
//NSData *newReceipt = transaction.transactionReceipt;
//NSArray *savedReceipts = [storage arrayForKey:@"receipts"];
//if (!savedReceipts) {
//    // Storing the first receipt
//    [storage setObject:@[newReceipt] forKey:@"receipts"];
//} else {
//    // Adding another receipt
//    NSArray *updatedReceipts = [savedReceipts arrayByAddingObject:newReceipt];
//    [storage setObject:updatedReceipts forKey:@"receipts"];
//}
//
//[storage synchronize];

/*
*	The WalletController maintains the bought pin points of the user and, in future releases, the already bought premium features, as well as enabling them on the user's demand.
*	Every local action, that reduces the amount of the bought pin points, including transfering them to a remote p2p device with the same Apple ID, has to be requested and granted through this class.
*/
final class WalletController {
	/* Never change this value after the first App Store release! */
	static let pinCost = 10
    static let initialPinPoints = 200
	
    static let PinPointPrefKey = "PinPointPrefKey"
    private static let PinPointQueueLabel = "Pin Point Queue"
    private static let pinPointQueue = dispatch_queue_create(PinPointQueueLabel, DISPATCH_QUEUE_SERIAL)
    
    private struct Singleton {
        static var points: Int!
        static var token: dispatch_once_t = 0
    }
    
    private static var _availablePinPoints: Int {
        get {
            dispatch_once(&Singleton.token, { () -> Void in
                Singleton.points = NSUserDefaults.standardUserDefaults().integerForKey(PinPointPrefKey) ?? 200
            })
            
            return Singleton.points
        }
        
        set {
            Singleton.points = newValue
            NSUserDefaults.standardUserDefaults().setInteger(newValue, forKey: PinPointPrefKey)
            NSUserDefaults.standardUserDefaults().synchronize()
        }
    }
    
    static var availablePinPoints: Int {
        var result: Int = 0
        dispatch_sync(pinPointQueue) {
            result = _availablePinPoints
        }
        return result
	}
    
    private static func decreasePinPoints(by: Int) {
        dispatch_async(pinPointQueue) {
            _availablePinPoints -= by
        }
    }
    
    static func increasePinPoints(by: Int) {
        dispatch_async(pinPointQueue) {
            _availablePinPoints += by
        }
    }
	
    static func requestPin(confirmCallback: (PinConfirmation) -> Void) {
        let title = NSLocalizedString("Spend Pin Points", comment: "Title of the alert which pops up when the user is about to spend in-app currency.")
        var message: String
        var actions: [UIAlertAction] = [UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .Cancel, handler: nil)]
        
		if _availablePinPoints >= pinCost {
            message = NSLocalizedString("You have %d pin points available.", comment: "Alert message if the user is about to spend in-app currency and has enough of it in his pocket.")
            message = String(format: message, WalletController._availablePinPoints)
            let actionTitle = String(format: NSLocalizedString("Spend %d of them", comment: "The user accepts to spend pin points for this action."), WalletController.pinCost)
            actions.append(UIAlertAction(title: actionTitle, style: .Default) { action in
                confirmCallback(PinConfirmation())
            })
        } else {
            message = NSLocalizedString("You do not have enough pin points available.", comment: "Alert message if the user is about to buy something and has not enough of in-app money in his pocket.")
            actions.append(UIAlertAction(title: NSLocalizedString("Visit Shop", comment: "Title of action which opens the shop view."), style: .Default) { action in
                guard let rootTabBarController = UIApplication.sharedApplication().keyWindow?.rootViewController as? UITabBarController else { return }
                
                rootTabBarController.selectedIndex = 2
            })
        }
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .ActionSheet)
        for action in actions {
            alertController.addAction(action)
        }
        alertController.present(nil)
	}
    
    static func redeem(confirmation: PinConfirmation) {
        dispatch_once(&confirmation.token, { () -> Void in
            decreasePinPoints(pinCost)
        })
    }
    
    class PinConfirmation {
        private var token: dispatch_once_t = 0
        var redeemed: Bool { return token != 0 }
        
        private init() {}
    }
}