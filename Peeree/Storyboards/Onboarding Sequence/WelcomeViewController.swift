//
//  WelcomeViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 12.10.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import UIKit

final class WelcomeViewController: UIViewController {
	@IBOutlet private var infoButton: UIButton!
	
	override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
		if !animated {
			//at the very first showing, the view appears unanimated, so only here we want to show the animation
			self.view.flyInSubviews([infoButton], duration: 2.0, delay: 0.5, damping: 1.0, velocity: 1.0)
//			let endPos = infoButton.frame
//			
//			infoButton.frame.origin.y = self.view.frame.height
//			infoButton.alpha = 0.0
//			
//			UIView.animateWithDuration(2.0, delay: 1.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 1.0, options: UIViewAnimationOptions(rawValue: 0), animations: { () -> Void in
//				self.infoButton.frame = endPos
//				self.infoButton.alpha = 1.0
//				}, completion: nil)
		}
	}
}
