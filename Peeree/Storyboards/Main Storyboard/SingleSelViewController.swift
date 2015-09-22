//
//  SingleSelViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class SingleSelViewController: UIViewController {
	@IBOutlet var headingLabel: UILabel!
	@IBOutlet var subHeadingLabel: UILabel!
	@IBOutlet var descriptionTextView: UITextView!
	@IBOutlet var selectionPickerView: UIPickerView!
	
	internal var dataSource: SingleSelViewControllerDataSource!
	
	override func shouldPerformSegueWithIdentifier(identifier: String, sender: AnyObject?) -> Bool {
		NSLog("SingleSelViewController.%@", __FUNCTION__)
		return true
	}
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		NSLog("SingleSelViewController.%@", __FUNCTION__)
	}
	
	override func performSegueWithIdentifier(identifier: String, sender: AnyObject?) {
		NSLog("SingleSelViewController.%@", __FUNCTION__)
		super.performSegueWithIdentifier(identifier, sender: sender)
	}
	
	override func didMoveToParentViewController(parent: UIViewController?) {
		if dataSource != nil {
			headingLabel.text = dataSource.headingOfSingleSelViewController(self)
			subHeadingLabel.text = dataSource.subHeadingOfSingleSelViewController(self)
			selectionPickerView.dataSource = dataSource
			selectionPickerView.delegate = dataSource
			descriptionTextView.text = dataSource.descriptionOfSingleSelViewController(self)
		}
	}
}

protocol SingleSelViewControllerDataSource: UIPickerViewDataSource, UIPickerViewDelegate {
	func headingOfSingleSelViewController(singleSelViewController: SingleSelViewController) -> String?
	func subHeadingOfSingleSelViewController(singleSelViewController: SingleSelViewController) -> String?
	func descriptionOfSingleSelViewController(singleSelViewController: SingleSelViewController) -> String?
}
