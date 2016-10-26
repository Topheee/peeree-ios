//
//  BasicInfoViewContoller.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class BasicInfoViewContoller: UIViewController {
	@IBOutlet private var backButton: UIButton!
	
	override func viewDidLoad() {
		backButton.alpha = 0.0
	}
	
	override func viewDidAppear(_ animated: Bool) {
		UIView.animate(withDuration: 2.0, delay: 1.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 1.0, options: UIViewAnimationOptions.allowUserInteraction, animations: { () -> Void in
			self.backButton.alpha = 1.0
		}, completion: nil)
	}
}
