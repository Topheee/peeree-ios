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
        case pinPointOffering, walletInfo, noInAppPurchase, transaction
    }
    
    private enum SectionID: Int {
        case wallet=0, products, transactions
    }
    
    private let purchaser = InAppPurchaseController.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        refreshControl = UIRefreshControl()
        refreshControl?.attributedTitle = NSAttributedString(string: NSLocalizedString("Reloading Products", comment: "Title of the refresh control of the shop view."))
        refreshControl?.addTarget(self, action: #selector(refreshTable(_:)), for: .valueChanged)
        
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        purchaser.delegate = self
        if (!purchaser.isLoadingProducts || purchaser.currentProducts == nil) && Reachability.getNetworkStatus() != .notReachable {
            refreshControl?.beginRefreshing()
            purchaser.requestProducts()
        }
        // why? i don't know
        self.tableView.backgroundColor = AppDelegate.shared.theme.globalBackgroundColor
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
                return tableView.dequeueReusableCell(withIdentifier: CellID.noInAppPurchase.rawValue, for: indexPath)
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
                return InAppPurchaseController.shared.currentProducts?.count ?? 0
            } else {
                return 1
            }
        case .transactions:
            return SKPaymentQueue.default().transactions.count
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
            return SKPaymentQueue.default().transactions.count > 0 ? NSLocalizedString("Transactions", comment: "Title for section containing in-app purchase transactions.") : nil
		}
	}
	
	override func numberOfSections(in tableView: UITableView) -> Int {
        return SKPaymentQueue.default().transactions.count > 0 ? 3 : 2
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 1 && SKPaymentQueue.canMakePayments() else { return }
        guard let product = InAppPurchaseController.shared.currentProducts?[indexPath.row] else { return }
        
        let localizedTitleFormat = NSLocalizedString("Buy %@ for %@ ,-", comment: "Title of the alert which pops up when the user is about to buy in-app purchase products (such as Pin Points). At the first placeholder the product name is inserted, at the second the price.")
        let title = String(format: localizedTitleFormat, product.localizedTitle, InAppPurchaseController.getProductPrize(of: product))
        
        let alertController = UIAlertController(title: title, message: product.localizedDescription, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Verb."), style: .cancel, handler: nil))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Buy", comment: "Verb."), style: .default, handler: { (action) in
            InAppPurchaseController.shared.makePaymentRequest(for: product)
        }))
        
        alertController.present(nil)
    }
    
    // MARK: InAppPurchaseDelegate
    
    func updateTransactions(_ transactions: [SKPaymentTransaction]) {
        tableView.reloadSections(IndexSet(integer: 2), with: .automatic)
    }
    
    func productsLoaded(error: Error?) {
        if error != nil {
            AppDelegate.display(networkError: error!, localizedTitle: NSLocalizedString("Reloading Products Failed", comment: "Title of alert"))
        }
        DispatchQueue.main.async {
            self.refreshControl?.endRefreshing()
            self.tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
        }
    }
    
    func transactionFailed(error: Error) {
        let alert = UIAlertController(title: NSLocalizedString("Store Error", comment: "Title of alert when an error with in-app purchases occurred."), message: error.localizedDescription, preferredStyle: .alert)
        alert.present(nil)
    }
    
    @objc
    private func refreshTable(_ sender: AnyObject?) {
//        guard let reachability = Reachability() else { refreshControl?.endRefreshing(); return }
//        reachability.startNotifier()
        
        switch Reachability.getNetworkStatus() {
        case .notReachable:
            refreshControl?.endRefreshing()
        case .reachableViaWiFi, .reachableViaWWAN:
            purchaser.requestProducts()
            InAppPurchaseController.refreshPinPoints()
        }
    }
    
    private func createWalletInfoCell(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let ret = tableView.dequeueReusableCell(withIdentifier: CellID.walletInfo.rawValue, for: indexPath)
        switch indexPath.row {
        case 0:
            ret.textLabel?.text = NSLocalizedString("Pin Points", comment: "Plural form of the in-app currency.")
            ret.detailTextLabel?.text = String(InAppPurchaseController.availablePinPoints)
            break
        default:
            break
        }
        return ret
    }
    
    private func createPinPointOfferingCell(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        guard let products = InAppPurchaseController.shared.currentProducts else { assertionFailure(); return UITableViewCell() }
        
        let ret = tableView.dequeueReusableCell(withIdentifier: CellID.pinPointOffering.rawValue, for: indexPath)
        let numberFormatter = NumberFormatter()
        numberFormatter.formatterBehavior = .behavior10_4
        numberFormatter.numberStyle = .currency
        numberFormatter.locale = products[indexPath.row].priceLocale
        ret.textLabel?.text = products[indexPath.row].localizedTitle
        ret.detailTextLabel?.text = InAppPurchaseController.getProductPrize(of: products[indexPath.row])
        return ret
    }
    
    private func createTransactionCell(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let ret = tableView.dequeueReusableCell(withIdentifier: CellID.transaction.rawValue, for: indexPath) as! TransactionTableViewCell
        
        let ongoingTransactions = SKPaymentQueue.default().transactions
        let transaction = ongoingTransactions[indexPath.row]
        let localizedFormat = NSLocalizedString("Buying %d x %@ Pin Points", comment: "Cell title of ongoing transaction rows.")
        let pinPoints = String(describing: InAppPurchaseController.getPinPoints(inProductID: transaction.payment.productIdentifier))
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
