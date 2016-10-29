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
	@IBOutlet private weak var headingLabel: UILabel!
	@IBOutlet private weak var subHeadingLabel: UILabel!
	@IBOutlet private weak var descriptionTextView: UITextView!
	
	var dataSource: BasicDescriptionViewControllerDataSource?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let dataSource = dataSource else { return }
        
        headingLabel.text = dataSource.headingOfBasicDescriptionViewController(self)
        subHeadingLabel.text = dataSource.subHeadingOfBasicDescriptionViewController(self)
        descriptionTextView.text = dataSource.descriptionOfBasicDescriptionViewController(self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        descriptionTextView.flashScrollIndicators()
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
}

protocol BasicDescriptionViewControllerDataSource {
	func headingOfBasicDescriptionViewController(_ basicDescriptionViewController: BasicDescriptionViewController) -> String?
	func subHeadingOfBasicDescriptionViewController(_ basicDescriptionViewController: BasicDescriptionViewController) -> String?
	func descriptionOfBasicDescriptionViewController(_ basicDescriptionViewController: BasicDescriptionViewController) -> String?
}
