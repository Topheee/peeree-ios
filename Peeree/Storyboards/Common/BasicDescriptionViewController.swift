//
//  BasicDescriptionViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 08.01.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

/// View controller for simple view with Heading, Subheading and descriptive text. Is embedded in other ViewControllers.
final class BasicDescriptionViewController: UIViewController {
	@IBOutlet private var headingLabel: UILabel!
	@IBOutlet private var subHeadingLabel: UILabel!
	@IBOutlet private var descriptionTextView: UITextView!
	
	var dataSource: BasicDescriptionViewControllerDataSource?
	
	override func didMoveToParentViewController(parent: UIViewController?) {
		super.didMoveToParentViewController(parent)
		if let dataSource = dataSource {
			headingLabel.text = dataSource.headingOfBasicDescriptionViewController(self)
			subHeadingLabel.text = dataSource.subHeadingOfBasicDescriptionViewController(self)
			descriptionTextView.text = dataSource.descriptionOfBasicDescriptionViewController(self)
		}
	}
}

protocol BasicDescriptionViewControllerDataSource {
	func headingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String?
	func subHeadingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String?
	func descriptionOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String?
}
