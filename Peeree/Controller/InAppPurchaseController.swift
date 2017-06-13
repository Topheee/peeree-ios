//
//  InAppPurchaseController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 13.08.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import Foundation
import StoreKit

protocol InAppPurchaseDelegate: class {
    func productsLoaded(error: Error?)
    func updateTransactions(_ transactions: [SKPaymentTransaction])
    func transactionFailed(error: Error)
}

/*
 *  This singleton is in charge of managing the process of all in-app purchases. Thus it is the endpoint for both incoming and outgoing messages to and from Apple's servers, provided by the StoreKit API.
 *	It maintains the bought pin points of the user and, in future releases, the already bought premium features, as well as enabling them on the user's demand.
 *	Every local action, that reduces the amount of the bought pin points, including transfering them to a remote p2p device with the same Apple ID, has to be requested and granted through this class.
 */
final class InAppPurchaseController: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    /* Never change this value after the first App Store release! */
    public static let PinCosts: PinPoints = 10
    static let InitialPinPoints: PinPoints = 50
    
    static let PinPointPrefKey = "PinPointPrefKey"
    private static let PinPointQueueLabel = "Pin Point Queue"
    private static let pinPointQueue = DispatchQueue(label: PinPointQueueLabel, attributes: [])
    
    private static var __once: () = { () -> Void in
        if UserDefaults.standard.value(forKey: PinPointPrefKey) == nil {
            Singleton.points = InitialPinPoints
        } else {
            Singleton.points = PinPoints(UserDefaults.standard.integer(forKey: PinPointPrefKey))
        }
    }()
    private struct Singleton {
        static var points: PinPoints!
    }
    
    private static var _availablePinPoints: PinPoints {
        get {
            _ = InAppPurchaseController.__once
            
            return Singleton.points
        }
        
        set {
            Singleton.points = newValue
            UserDefaults.standard.set(newValue, forKey: PinPointPrefKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    public static var availablePinPoints: PinPoints {
        var result: PinPoints = 0
        pinPointQueue.sync {
            result = _availablePinPoints
        }
        return result
    }
    
    public static func decreasePinPoints(by: PinPoints = PinCosts) {
        pinPointQueue.async {
            _availablePinPoints -= by
        }
    }
    
    public static func increasePinPoints(by: PinPoints) {
        pinPointQueue.async {
            _availablePinPoints += by
        }
    }
    
    static func getPinPoints(inProductID: String) -> PinPoints? {
        let prefix = "com.peeree.pin_points_"
        guard inProductID.hasPrefix(prefix) else { return nil }
        
        let len = prefix.characters.count
        let pinPointsString = inProductID.substring(from: inProductID.characters.index(inProductID.startIndex, offsetBy: len))
        return PinPoints(pinPointsString)
    }
    
    static func refreshPinPoints() {
        AccountController.shared.getPinPoints { (_pinPoints, _error) in
            guard _error != nil else {
                NSLog("could not refresh pin points: \(_error!)")
                return
            }
            if let pinPoints = _pinPoints {
                self.pinPointQueue.async {
                    self._availablePinPoints = pinPoints
                }
            }
        }
    }
    
    static func getProductPrize(of product: SKProduct) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.formatterBehavior = .behavior10_4
        numberFormatter.numberStyle = .currency
        numberFormatter.locale = product.priceLocale
        return numberFormatter.string(from: product.price)!
    }
    
    static let shared = InAppPurchaseController()
    
    private var currentProductsRequest: SKProductsRequest?
    private var _currentProducts: [SKProduct]?
    
    var currentProducts: [SKProduct]? { return _currentProducts }
    var isLoadingProducts: Bool { return currentProductsRequest != nil }
    
    weak var delegate: InAppPurchaseDelegate?
    
    /// Make a product request at Apple's servers.
    func requestProducts() {
        AccountController.shared.getProductIDs { (_productIDs, _error) in
            if let productIDs = _productIDs {
                let productsRequest = SKProductsRequest(productIdentifiers: Set<String>(productIDs))
                
                // Keep a strong reference to the request to prevent ARC from deallocating it while it's doing its job.
                self.currentProductsRequest = productsRequest
                productsRequest.delegate = self
                productsRequest.start()
            }
            
            self.delegate?.productsLoaded(error: _error)
        }
    }
    
    /// Make a payment request at Apple's servers for the specified product.
    func makePaymentRequest(for product: SKProduct) {
        let payment = SKMutablePayment(product: product)
        payment.quantity = 1
        // TODO payment.applicationUsername = encrypted UserPeerInfo.instance.peer.peerID.uuidString with our private key
        SKPaymentQueue.default().add(payment)
    }
    
    func clearCache() {
        _currentProducts = nil
        if currentProductsRequest != nil {
            currentProductsRequest = nil
            delegate?.productsLoaded(error: nil)
        }
    }
    
    // MARK: SKProductsRequestDelegate
    
    @objc func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        _currentProducts = response.products
        currentProductsRequest = nil
        
        for invalidIdentifier:String in response.invalidProductIdentifiers {
            NSLog("Invalid product identifier \(invalidIdentifier)")
        }
    
        delegate?.productsLoaded(error: nil)
    }
    
    // MARK: SKPaymentTransactionObserver
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedDownloads downloads: [SKDownload]) {
        // we have no downloads from Apple's servers
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        // Is handled by the updatedTransactions purchased or failed case
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch (transaction.transactionState) {
            // Call the appropriate custom method for the transaction state.
            case .purchasing:
                // Update UI to reflect the in-progress status, and wait to be called again.
                break
            case .deferred:
                // Update UI to reflect the deferred status, and wait to be called again.
                break
            case .failed:
                // Use the value of the error property to present a message to the user.
                fail(transaction: transaction)
            case .purchased:
                // Provide the purchased functionality.
                complete(transaction: transaction)
            case .restored:
                // Restore the previously purchased functionality.
                // [self restoreTransaction:transaction];
                break // we have no non-consumable products
            }
        }
        delegate?.updateTransactions(transactions)
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        // we have no non-consumable content yet
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        // we have no non-consumable content yet
    }
    
    private func complete(transaction: SKPaymentTransaction) {
        // TODO error handling
        guard let url = Bundle.main.appStoreReceiptURL, let receiptData = try? Data(contentsOf: url) else { assertionFailure(); return }
        
        AccountController.shared.redeem(receipts: receiptData) { (_pinPoints, _error) in
            guard _error != nil else {
                NSLog("could not redeem pin points: \(_error!)")
                return
            }
            if let pinPoints = _pinPoints {
                InAppPurchaseController.pinPointQueue.async {
                    InAppPurchaseController._availablePinPoints = pinPoints
                }
            } else {
                NSLog("server did not send pin points along, trying to retrieve them")
                InAppPurchaseController.refreshPinPoints()
            }
            SKPaymentQueue.default().finishTransaction(transaction)
        }
    }
    
    private func fail(transaction: SKPaymentTransaction) {
        if let error = transaction.error {
            delegate?.transactionFailed(error: error)
        }
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }
}
