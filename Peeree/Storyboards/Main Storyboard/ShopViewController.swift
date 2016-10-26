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
    
    private enum SectionID: Int {
        case wallet=0, products, transactions
    }
    
    private let inAppPurchaser = InAppPurchaseController.sharedController
    
    private var ongoingTransactions = Set<SKPaymentTransaction>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        refreshControl = UIRefreshControl()
        refreshControl?.attributedTitle = NSAttributedString(string: NSLocalizedString("Reloading Products", comment: "Title of the refresh control of the shop view."))
        refreshControl?.addTarget(self, action: #selector(refreshTable(_:)), for: .valueChanged)
        
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        inAppPurchaser.delegate = self
        if (!inAppPurchaser.isLoadingProducts || inAppPurchaser.currentProducts == nil) && Reachability.getNetworkStatus() != .notReachable {
            refreshControl?.beginRefreshing()
            inAppPurchaser.requestProducts()
        }
        // why? i don't know
        self.tableView.backgroundColor = theme.globalBackgroundColor
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        inAppPurchaser.delegate = nil
    }
    
    // - MARK: UITableView Data Source
	
	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionID = SectionID(rawValue: indexPath.section) else { return UITableViewCell() }
        
		switch sectionID {
		case .wallet:
			return createWalletInfoCell(tableView, indexPath: indexPath)
		case .products:
            if SKPaymentQueue.canMakePayments() {
                return createPinPointOfferingCell(tableView, indexPath:  indexPath)
            } else {
                return tableView.dequeueReusableCell(withIdentifier: CellID.NoInAppPurchase.rawValue, for: indexPath)
            }
        case .transactions:
            return createTransactionCell(tableView, indexPath: indexPath)
		}
	}
	
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionID = SectionID(rawValue: section) else { return 0 }
        
        switch sectionID {
		case .wallet:
			return 1
        case .products:
            if SKPaymentQueue.canMakePayments() {
                return InAppPurchaseController.sharedController.currentProducts?.count ?? 0
            } else {
                return 1
            }
        case .transactions:
            return ongoingTransactions.count
		}
	}
	
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionID = SectionID(rawValue: section) else { return nil }
        
        switch sectionID {
        case .wallet:
            return NSLocalizedString("Wallet", comment: "Heading for the table view section which contains information about the user's account.")
        case .products:
            if SKPaymentQueue.canMakePayments() {
                return NSLocalizedString("Products", comment: "Heading for the offerings of the in-app purchase products.")
            } else {
                return nil
            }
        case .transactions:
            return ongoingTransactions.count > 0 ? NSLocalizedString("Transactions", comment: "Title for section containing in-app purchase transactions.") : nil
		}
	}
	
	override func numberOfSections(in tableView: UITableView) -> Int {
        return ongoingTransactions.count > 0 ? 3 : 2
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 1 && SKPaymentQueue.canMakePayments() else { return }
        guard let product = InAppPurchaseController.sharedController.currentProducts?[indexPath.row] else { return }
        
        let localizedTitleFormat = NSLocalizedString("Buy %@ for %@ ,-", comment: "Title of the alert which pops up when the user is about to buy in-app purchase products (such as Pin Points). At the first placeholder the product name is inserted, at the second the price.")
        let title = String(format: localizedTitleFormat, product.localizedTitle, InAppPurchaseController.getProductPrize(forProduct: product))
        
        let alertController = UIAlertController(title: title, message: product.localizedDescription, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Verb."), style: .cancel, handler: nil))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Buy", comment: "Verb."), style: .default, handler: { (action) in
            InAppPurchaseController.sharedController.makePaymentRequest(forProduct: product)
        }))
        
        alertController.present(nil)
    }
    
    // MARK: InAppPurchaseDelegate
    
    func updateTransactions(_ transactions: [SKPaymentTransaction]) {
        tableView.reloadSections(IndexSet(integer: 2), with: .automatic)
    }
    
    func productsLoaded() {
        refreshControl?.endRefreshing()
        tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
    }
    
    @objc
    private func refreshTable(_ sender: AnyObject?) {
//        guard let reachability = Reachability() else { refreshControl?.endRefreshing(); return }
//        reachability.startNotifier()
        
        switch Reachability.getNetworkStatus() {
        case .notReachable:
            refreshControl?.endRefreshing()
        case .reachableViaWiFi, .reachableViaWWAN:
            inAppPurchaser.requestProducts()
        }
    }
    
    private func createWalletInfoCell(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let ret = tableView.dequeueReusableCell(withIdentifier: CellID.WalletInfo.rawValue, for: indexPath)
        switch indexPath.row {
        case 0:
            ret.textLabel?.text = NSLocalizedString("Pin Points", comment: "Plural form of the in-app currency.")
            ret.detailTextLabel?.text = String(WalletController.availablePinPoints)
            break
        default:
            break
        }
        return ret
    }
    
    private func createPinPointOfferingCell(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        guard let products = InAppPurchaseController.sharedController.currentProducts else { assertionFailure(); return UITableViewCell() }
        
        let ret = tableView.dequeueReusableCell(withIdentifier: CellID.PinPointOffering.rawValue, for: indexPath)
        let numberFormatter = NumberFormatter()
        numberFormatter.formatterBehavior = .behavior10_4
        numberFormatter.numberStyle = .currency
        numberFormatter.locale = products[indexPath.row].priceLocale
        ret.textLabel?.text = products[indexPath.row].localizedTitle
        ret.detailTextLabel?.text = InAppPurchaseController.getProductPrize(forProduct: products[indexPath.row])
        return ret
    }
    
    private func createTransactionCell(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let ret = tableView.dequeueReusableCell(withIdentifier: CellID.Transaction.rawValue, for: indexPath) as! TransactionTableViewCell
        
        let transaction = ongoingTransactions[ongoingTransactions.index(ongoingTransactions.startIndex, offsetBy: indexPath.row)]
        let localizedFormat = NSLocalizedString("Buying %d x %@ Pin Points", comment: "Cell title of ongoing transaction rows.")
        let pinPoints = String(describing: InAppPurchaseController.getPinPoints(inProduct: transaction.payment.productIdentifier))
        ret.titleLabel.text = String(format: localizedFormat, transaction.payment.quantity, pinPoints)
        switch transaction.transactionState {
        case .deferred:
            ret.activityIndicator.stopAnimating()
        case .purchasing:
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
