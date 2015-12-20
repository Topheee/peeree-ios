//
//  ScrollableInfoViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import UIKit

class ScrollableInfoViewController: BasicInfoViewContoller {
	@IBOutlet var scrollView: UIScrollView!
	@IBOutlet var contentView: UIView!
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		
		scrollView.layoutIfNeeded()
		scrollView.contentSize = contentView.bounds.size
	}

}
