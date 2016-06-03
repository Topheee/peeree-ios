//
//  DateSelViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 04.01.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

class DateSelViewController: UIViewController {
	@IBOutlet private var datePickerView: UIDatePicker!
	
	var dataSource: DateSelViewControllerDataSource?
//		{
//		didSet {
//			descriptionVC.dataSource = dataSource
//		}
//	}
	
	// MARK: - Navigation
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		super.prepareForSegue(segue, sender: sender)
		if let descriptionVC = segue.destinationViewController as? BasicDescriptionViewController {
			descriptionVC.dataSource = dataSource
		}
	}
	
	override func didMoveToParentViewController(parent: UIViewController?) {
		super.didMoveToParentViewController(parent)
		dataSource?.setupPicker(datePickerView, inDateSel: self)
	}
}

protocol DateSelViewControllerDataSource: BasicDescriptionViewControllerDataSource {
	func setupPicker(picker: UIDatePicker, inDateSel dateSelViewController: DateSelViewController) -> Void
}
