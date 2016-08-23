//
//  InAppPurchaseController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 13.08.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import Foundation
import StoreKit

/*
 *  This singleton is in charge of managing the process of all in-app purchases. Thus it is the endpoint for both incoming and outgoing messages to and from Apple's servers, provided by the StoreKit API.
 */
final class InAppPurchaseController: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    static let sharedController = InAppPurchaseController()
    
    private var currentProductsRequest: SKProductsRequest?
    private var _currentProducts: [SKProduct]?
    
    private var productIdentifiers: [String]? {
        guard let url = NSBundle.mainBundle().URLForResource("product_ids", withExtension:"plist") else { assertionFailure(); return nil }
        return NSArray(contentsOfURL: url) as? [String]
    }
    
    var currentProducts: [SKProduct]? { return _currentProducts }
    var isLoadingProducts: Bool { return currentProductsRequest != nil }
    
    weak var delegate: InAppPurchaseDelegate?
    
    static func getPinPoints(inProduct productID: String) -> Int? {
        let prefix = "com.peeree.pin_points_"
        guard productID.hasPrefix(prefix) else { return nil }
        
        let len = prefix.characters.count
        let pinPointsString = productID.substringFromIndex(productID.startIndex.advancedBy(len))
        return Int(pinPointsString)
    }
    
    static func getProductPrize(forProduct product: SKProduct) -> String {
        let numberFormatter = NSNumberFormatter()
        numberFormatter.formatterBehavior = .Behavior10_4
        numberFormatter.numberStyle = .CurrencyStyle
        numberFormatter.locale = product.priceLocale
        return numberFormatter.stringFromNumber(product.price)!
    }
    
    /// Make a product request at Apple's servers.
    func requestProducts() {
        guard let productIDs = productIdentifiers else { assertionFailure(); return }

        let productsRequest = SKProductsRequest(productIdentifiers: Set<String>(productIDs))
        
        // Keep a strong reference to the request to prevent ARC from deallocating it while it's doing its job.
        currentProductsRequest = productsRequest
        productsRequest.delegate = self
        productsRequest.start()
    }
    
    /// Make a payment request at Apple's servers for the specified product.
    func makePaymentRequest(forProduct product: SKProduct) {
        let payment = SKMutablePayment(product: product)
        payment.quantity = 1
//        payment.applicationUsername = UIDevice.currentDevice().identifierForVendor
        SKPaymentQueue.defaultQueue().addPayment(payment)
    }
    
    func clearCache() {
        _currentProducts = nil
        if currentProductsRequest != nil {
            currentProductsRequest = nil
            delegate?.productsLoaded()
        }
    }
    
    // MARK: SKProductsRequestDelegate
    
    @objc func productsRequest(request: SKProductsRequest, didReceiveResponse response: SKProductsResponse) {
        _currentProducts = response.products
        currentProductsRequest = nil
        
        for invalidIdentifier:String in response.invalidProductIdentifiers {
            NSLog("Invalid product identifier \(invalidIdentifier)")
        }
    
//        WalletNotification.ProductsLoaded.post()
        delegate?.productsLoaded()
    }
    
    // MARK: SKPaymentTransactionObserver
    
    func paymentQueue(queue: SKPaymentQueue, updatedDownloads downloads: [SKDownload]) {
        // we have no downloads from Apple's servers
    }
    
    func paymentQueue(queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        // Is handled by the updatedTransactions purchased or failed case
    }
    
    func paymentQueue(queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch (transaction.transactionState) {
            // Call the appropriate custom method for the transaction state.
            case .Purchasing:
                // Update UI to reflect the in-progress status, and wait to be called again.
                break
            case .Deferred:
                // Update UI to reflect the deferred status, and wait to be called again.
                break
            case .Failed:
                // Use the value of the error property to present a message to the user.
                self.failedTransaction(transaction)
            case .Purchased:
                // Provide the purchased functionality.
                completeTransaction(transaction)
            case .Restored:
                // Restore the previously purchased functionality.
                // [self restoreTransaction:transaction];
                break // we have no non-consumable products
            }
        }
        delegate?.updateTransactions(transactions)
    }
    
    func paymentQueue(queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: NSError) {
        // we have no non-consumable content yet
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(queue: SKPaymentQueue) {
        // we have no non-consumable content yet
    }
    
    private func completeTransaction(transaction: SKPaymentTransaction) {
        // TODO handle the cases of the assertionFailure
        guard let pinPoints = InAppPurchaseController.getPinPoints(inProduct: transaction.payment.productIdentifier) else { assertionFailure(); return }
        
        WalletController.increasePinPoints(pinPoints)
        
        SKPaymentQueue.defaultQueue().finishTransaction(transaction)
    }
    
    private func failedTransaction(transaction: SKPaymentTransaction) {
        SKPaymentQueue.defaultQueue().finishTransaction(transaction)
    }
    
//    - (void)fetchProductIdentifiersFromURL:(NSURL *)url delegate:(id)delegate
//    {
//    dispatch_queue_t global_queue =
//    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
//    dispatch_async(global_queue, ^{
//    NSError *err;
//    NSData *jsonData = [NSData dataWithContentsOfURL:url
//    options:NULL
//    error:&err];
//    if (!jsonData) { /* Handle the error */ }
//    
//    NSArray *productIdentifiers = [NSJSONSerialization
//    JSONObjectWithData:jsonData options:NULL error:&err];
//    if (!productIdentifiers) { /* Handle the error */ }
//    
//    dispatch_queue_t main_queue = dispatch_get_main_queue();
//    dispatch_async(main_queue, ^{
//    [delegate displayProducts:productIdentifiers]; // Custom method
//    });
//    });
//    }
    
    private override init() {
        super.init()
        SKPaymentQueue.defaultQueue().addTransactionObserver(self)
    }
}

protocol InAppPurchaseDelegate: class {
    func productsLoaded()
    func updateTransactions(transactions: [SKPaymentTransaction])
}