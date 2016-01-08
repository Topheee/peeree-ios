//
//  BasicDescriptionViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 08.01.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

class BasicDescriptionViewController: UIViewController {
	@IBOutlet var headingLabel: UILabel!
	@IBOutlet var subHeadingLabel: UILabel!
	@IBOutlet var descriptionTextView: UITextView!
	
	var dataSource: BasicDescriptionViewControllerDataSource?
	
	override func didMoveToParentViewController(parent: UIViewController?) {
		super.didMoveToParentViewController(parent)
		if let dataSource = dataSource {
			headingLabel.text = dataSource.headingOfBasicDescriptionViewController(self)
			subHeadingLabel.text = dataSource.subHeadingOfBasicDescriptionViewController(self)
			descriptionTextView.text = dataSource.descriptionOfBasicDescriptionViewController(self)
		}
	}
	

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}

protocol BasicDescriptionViewControllerDataSource {
	func headingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String?
	func subHeadingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String?
	func descriptionOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String?
}
