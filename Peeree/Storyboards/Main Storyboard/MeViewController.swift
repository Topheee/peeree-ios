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
	@IBOutlet var countryTextField: UITextField!
	@IBOutlet var statusButton: UIButton!
	
	private let possibleStatuses = ["no comment", "married", "divorced", "going to be divorced", "in a relationship", "single"]
	
	override func performSegueWithIdentifier(identifier: String, sender: AnyObject?) {
		NSLog("MeViewController.%@", __FUNCTION__)
		super.performSegueWithIdentifier(identifier, sender: sender)
	}
	
	override func shouldPerformSegueWithIdentifier(identifier: String, sender: AnyObject?) -> Bool {
		NSLog("MeViewController.%@", __FUNCTION__)
		return true
	}
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		NSLog("MeViewController.%@", __FUNCTION__)
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		
		scrollView.layoutIfNeeded()
		scrollView.contentSize = contentView.bounds.size
	}
	
	func headingOfSingleSelViewController(singleSelViewController: SingleSelViewController) -> String? {
		return "Relationship status"
	}
	
	func subHeadingOfSingleSelViewController(singleSelViewController: SingleSelViewController) -> String? {
		return ""
	}
	
	func descriptionOfSingleSelViewController(singleSelViewController: SingleSelViewController) -> String? {
		return "Tell others, what's up with your relationship."
	}
	
	func numberOfComponentsInPickerView(pickerView: UIPickerView) -> Int {
		return 1
	}
	
	func pickerView(pickerView: UIPickerView,
		numberOfRowsInComponent component: Int) -> Int {
		return possibleStatuses.count
	}
	
	func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		return possibleStatuses[row]
	}
	
	func pickerView(pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
		statusButton.titleLabel?.text = possibleStatuses[row]
	}
}