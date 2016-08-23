//
//  ShopViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 11.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import UIKit
import StoreKit

final class ShopViewController: UITableViewController, InAppPurchaseDelegate {
    
    private enum CellID: String {
        case PinPointOffering, WalletInfo, NoInAppPurchase, Transaction
    }
    
    private let inAppPurchaser = InAppPurchaseController.sharedController
    
    private var ongoingTransactions = Set<SKPaymentTransaction>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        refreshControl = UIRefreshControl()
        refreshControl?.attributedTitle = NSAttributedString(string: NSLocalizedString("Reloading Products", comment: "Title of the refresh control of the shop view."))
        refreshControl?.addTarget(self, action: #selector(refreshTable(_:)), forControlEvents: .ValueChanged)
        
    }
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        inAppPurchaser.delegate = self
        if !inAppPurchaser.isLoadingProducts || inAppPurchaser.currentProducts == nil {
            refreshControl?.beginRefreshing()
            inAppPurchaser.requestProducts()
        }
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        inAppPurchaser.delegate = nil
    }
    
    // - MARK: UITableView Data Source
	
	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		switch indexPath.section {
		case 0:
			return createWalletInfoCell(tableView, indexPath: indexPath)
		case 1:
            if SKPaymentQueue.canMakePayments() {
                return createPinPointOfferingCell(tableView, indexPath:  indexPath)
            } else {
                return tableView.dequeueReusableCellWithIdentifier(CellID.NoInAppPurchase.rawValue, forIndexPath: indexPath)
            }
        case 2:
            return createTransactionCell(tableView, indexPath: indexPath)
		default:
			return UITableViewCell()
		}
	}
	
	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		switch section {
		case 0:
			return 2
        case 1:
            if SKPaymentQueue.canMakePayments() {
                return InAppPurchaseController.sharedController.currentProducts?.count ?? 0
            } else {
                return 1
            }
        case 2:
            return ongoingTransactions.count
		default:
			return 0
		}
	}
	
	override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return NSLocalizedString("Wallet", comment: "Heading for the table view section which contains information about the user's account.")
        case 1:
            if SKPaymentQueue.canMakePayments() {
                return NSLocalizedString("Products", comment: "Heading for the offerings of the in-app purchase products.")
            } else {
                return nil
            }
        case 2:
            return ongoingTransactions.count > 0 ? NSLocalizedString("Transactions", comment: "Title for section containing in-app purchase transactions.") : nil
		default:
			return nil
		}
	}
	
	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return ongoingTransactions.count > 0 ? 3 : 2
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        guard indexPath.section == 1 && SKPaymentQueue.canMakePayments() else { return }
        guard let product = InAppPurchaseController.sharedController.currentProducts?[indexPath.row] else { return }
        
        let localizedTitleFormat = NSLocalizedString("Buy %@ for %@ ,-", comment: "Title of the alert which pops up when the user is about to buy in-app purchase products (such as Pin Points). At the first placeholder the product name is inserted, at the second the price.")
        let title = String(format: localizedTitleFormat, product.localizedTitle, InAppPurchaseController.getProductPrize(forProduct: product))
        
        let alertController = UIAlertController(title: title, message: product.localizedDescription, preferredStyle: .ActionSheet)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Verb."), style: .Cancel, handler: nil))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Buy", comment: "Verb."), style: .Default, handler: { (action) in
            InAppPurchaseController.sharedController.makePaymentRequest(forProduct: product)
        }))
        
        alertController.present(nil)
    }
    
    // MARK: InAppPurchaseDelegate
    
    func updateTransactions(transactions: [SKPaymentTransaction]) {
        tableView.reloadSections(NSIndexSet(index: 2), withRowAnimation: .Automatic)
    }
    
    func productsLoaded() {
        refreshControl?.endRefreshing()
        tableView.reloadSections(NSIndexSet(index: 1), withRowAnimation: .Automatic)
    }
    
    @objc
    private func refreshTable(sender: AnyObject?) {
        inAppPurchaser.requestProducts()
    }
    
    private func createWalletInfoCell(tableView: UITableView, indexPath: NSIndexPath) -> UITableViewCell {
        let ret = tableView.dequeueReusableCellWithIdentifier(CellID.WalletInfo.rawValue, forIndexPath: indexPath)
        switch indexPath.row {
        case 0:
            ret.textLabel?.text = NSLocalizedString("Pin Points", comment: "Plural form of the in-app currency.")
            ret.detailTextLabel?.text = String(WalletController.availablePinPoints)
            break
        case 1:
            ret.textLabel?.text = NSLocalizedString("Account", comment: "")
            // TODO make this mutual or remove it
            ret.detailTextLabel?.text = "christopher@merlin.de"
            break
        default:
            break
        }
        return ret
    }
    
    private func createPinPointOfferingCell(tableView: UITableView, indexPath: NSIndexPath) -> UITableViewCell {
        guard let products = InAppPurchaseController.sharedController.currentProducts else { assertionFailure(); return UITableViewCell() }
        
        let ret = tableView.dequeueReusableCellWithIdentifier(CellID.PinPointOffering.rawValue, forIndexPath: indexPath)
        let numberFormatter = NSNumberFormatter()
        numberFormatter.formatterBehavior = .Behavior10_4
        numberFormatter.numberStyle = .CurrencyStyle
        numberFormatter.locale = products[indexPath.row].priceLocale
        ret.textLabel?.text = products[indexPath.row].localizedTitle
        ret.detailTextLabel?.text = InAppPurchaseController.getProductPrize(forProduct: products[indexPath.row])
        return ret
    }
    
    private func createTransactionCell(tableView: UITableView, indexPath: NSIndexPath) -> UITableViewCell {
        let ret = tableView.dequeueReusableCellWithIdentifier(CellID.Transaction.rawValue, forIndexPath: indexPath) as! TransactionTableViewCell
        
        let transaction = ongoingTransactions[ongoingTransactions.startIndex.advancedBy(indexPath.row)]
        let localizedFormat = NSLocalizedString("Buying %d x %@ Pin Points", comment: "Cell title of ongoing transaction rows.")
        let pinPoints = String(InAppPurchaseController.getPinPoints(inProduct: transaction.payment.productIdentifier)) ?? "?"
        ret.titleLabel.text = String(format: localizedFormat, transaction.payment.quantity, pinPoints)
        switch transaction.transactionState {
        case .Deferred:
            ret.activityIndicator.stopAnimating()
        case .Purchasing:
            ret.activityIndicator.startAnimating()
        default:
            assertionFailure("All other states should not appear in a cell (yet)")
        }
        return ret
    }
}

class TransactionTableViewCell: UITableViewCell {
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
}
