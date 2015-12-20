//
//  MainDataViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class MeViewController: UIViewController, SingleSelViewControllerDataSource {
	@IBOutlet var scrollView: UIScrollView!
	@IBOutlet var contentView: UIView!
	
	@IBOutlet var forenameTextField: UITextField!
	@IBOutlet var lastnameTextField: UITextField!
	@IBOutlet var ageTextField: UITextField!
	@IBOutlet var statusButton: UIButton!
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		if let singleSelVC = segue.destinationViewController as? SingleSelViewController {
			singleSelVC.dataSource = self
		} else if let charTraitVC = segue.destinationViewController as?
			CharacterTraitViewController {
			charTraitVC.characterTraits = LocalPeerManager.getLocalPeerDescription().characterTraits
		}
		// TODO remove this
//		else if let multipleSelVC = segue.destinationViewController as? UITableViewController {
//			multipleSelVC.title = NSLocalizedString("Spoken Languages", comment: "Title of the spoken languages selection view controller")
//			multipleSelVC.tableView.dataSource = self
//			multipleSelVC.tableView.delegate = self
//		}
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		
		scrollView.layoutIfNeeded()
		scrollView.contentSize = contentView.bounds.size
	}
	
	func headingOfSingleSelViewController(singleSelViewController: SingleSelViewController) -> String? {
		return NSLocalizedString("Relationship status", comment: "Heading of the relation ship status picker view controller")
	}
	
	func subHeadingOfSingleSelViewController(singleSelViewController: SingleSelViewController) -> String? {
		return ""
	}
	
	func descriptionOfSingleSelViewController(singleSelViewController: SingleSelViewController) -> String? {
		return NSLocalizedString("Tell others, what's up with your relationship.", comment: "Description of relation ship status picker view controller")
	}
	
	func numberOfComponentsInPickerView(pickerView: UIPickerView) -> Int {
		return 1
	}
	
	func pickerView(pickerView: UIPickerView,
		numberOfRowsInComponent component: Int) -> Int {
		return LocalPeerDescription.possibleStatuses.count
	}
	
	func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		return LocalPeerDescription.possibleStatuses[row]
	}
	
	func pickerView(pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
		statusButton.titleLabel?.text = LocalPeerDescription.possibleStatuses[row]
	}
}