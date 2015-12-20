//
//  ShopViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 11.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import UIKit
import StoreKit

class ShopViewController: UITableViewController {
	var products: SKProductsResponse?
	
	private func createWalletInfoCell(tableView: UITableView, indexPath: NSIndexPath) -> UITableViewCell {
		let ret = tableView.dequeueReusableCellWithIdentifier("walletInfoCell", forIndexPath: indexPath)
		switch indexPath.row {
		case 0:
			ret.textLabel?.text = NSLocalizedString("Pin Points", comment: "Plural form of the in-app currency")
			ret.detailTextLabel?.text = String(WalletController.getAvailablePinPoints())
			break
		case 1:
			ret.textLabel?.text = NSLocalizedString("Account", comment: "")
			// TODO make this mutual or remove it
			ret.detailTextLabel?.text = String("christopher@merlin.de")
			break
		default:
			break
		}
		return ret
	}
	
	private func createPinPointOfferingCell(tableView: UITableView, indexPath: NSIndexPath) -> UITableViewCell {
		let ret = tableView.dequeueReusableCellWithIdentifier("pinPointOfferingCell", forIndexPath: indexPath)
		let numberFormatter = NSNumberFormatter()
		// TODO I think we don't need this
		//numberFormatter.formatterBehavior = NSNumberFormatterBehavior10_4
		numberFormatter.numberStyle = .CurrencyStyle
		numberFormatter.locale = products?.products[indexPath.row].priceLocale
		ret.textLabel?.text = products?.products[indexPath.row].localizedTitle
		ret.detailTextLabel?.text = numberFormatter.stringFromNumber(products?.products[indexPath.row].price ?? 0)
		return ret
	}
	
	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		switch indexPath.section {
		case 0:
			return createWalletInfoCell(tableView, indexPath: indexPath)
		case 1:
			return createPinPointOfferingCell(tableView, indexPath:  indexPath)
		default:
			return UITableViewCell()
		}
	}
	
	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		switch section {
		case 0:
			return 2
		case 1:
			return products?.products.count ?? 0
		default:
			return 0
		}
	}
	
	override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch section {
		case 1:
			return NSLocalizedString("Pin Point Offerings", comment: "Heading for the offerings of the in-app currency")
		default:
			return nil
		}
	}
	
	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return 2
	}
}
