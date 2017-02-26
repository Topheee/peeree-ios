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
	static let PinCosts = 10
    static let InitialPinPoints = 200
	
    static let PinPointPrefKey = "PinPointPrefKey"
    private static let PinPointQueueLabel = "Pin Point Queue"
    private static let pinPointQueue = DispatchQueue(label: PinPointQueueLabel, attributes: [])
    
    private static var __once: () = { () -> Void in
        if UserDefaults.standard.value(forKey: PinPointPrefKey) == nil {
            Singleton.points = 200
        } else {
            Singleton.points = UserDefaults.standard.integer(forKey: PinPointPrefKey)
        }
    }()
    private struct Singleton {
        static var points: Int!
    }
    
    private static var _availablePinPoints: Int {
        get {
            _ = WalletController.__once
            
            return Singleton.points
        }
        
        set {
            Singleton.points = newValue
            UserDefaults.standard.set(newValue, forKey: PinPointPrefKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    static var availablePinPoints: Int {
        var result: Int = 0
        pinPointQueue.sync {
            result = _availablePinPoints
        }
        return result
	}
    
    private static func decreasePinPoints(by: Int) {
        pinPointQueue.async {
            _availablePinPoints -= by
        }
    }
    
    static func increasePinPoints(by: Int) {
        pinPointQueue.async {
            _availablePinPoints += by
        }
    }
	
    static func requestPin(_ confirmCallback: @escaping (PinConfirmation) -> Void) {
        let title = NSLocalizedString("Spend Pin Points", comment: "Title of the alert which pops up when the user is about to spend in-app currency.")
        var message: String
        var actions: [UIAlertAction] = [UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)]
        
		if _availablePinPoints >= PinCosts {
            message = NSLocalizedString("You have %d pin points available.", comment: "Alert message if the user is about to spend in-app currency and has enough of it in his pocket.")
            message = String(format: message, _availablePinPoints)
            let actionTitle = String(format: NSLocalizedString("Spend %d of them", comment: "The user accepts to spend pin points for this action."), PinCosts)
            actions.append(UIAlertAction(title: actionTitle, style: .default) { action in
                confirmCallback(PinConfirmation())
            })
        } else {
            message = NSLocalizedString("You do not have enough pin points available.", comment: "Alert message if the user is about to buy something and has not enough of in-app money in his pocket.")
            actions.append(UIAlertAction(title: NSLocalizedString("Visit Shop", comment: "Title of action which opens the shop view."), style: .default) { action in
                guard let rootTabBarController = UIApplication.shared.keyWindow?.rootViewController as? UITabBarController else { return }
                
                rootTabBarController.selectedIndex = 2
            })
        }
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        for action in actions {
            alertController.addAction(action)
        }
        alertController.present(nil)
	}
    
    static func redeem(confirmation: PinConfirmation) {
        confirmation.redeem {
            decreasePinPoints(by: PinCosts)
        }
    }
    
    class PinConfirmation {
        private var queue = DispatchQueue(label: "com.kobusch.peeree.pin_confirmation")
        private var _redeemed = false
        var redeemed: Bool { return queue.sync { return _redeemed } }
        
        fileprivate init() {}
        
        fileprivate func redeem(_ block: @escaping () -> Void) {
            queue.async {
                if !self._redeemed {
                    self._redeemed = true
                    block()
                }
            }
        }
    }
}
