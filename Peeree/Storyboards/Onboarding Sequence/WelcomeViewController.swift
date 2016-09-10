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
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        guard let vc = segue.destinationViewController as? OnboardingDescriptionViewController else { return }
        
        vc.infoType = .General
    }
	
	override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        infoButton.tintColor = theme.globalTintColor // for whatever reason we have to do that here...
		if !animated {
			//at the very first showing, the view appears unanimated, so only here we want to show the animation
			self.view.flyInSubviews([infoButton], duration: 2.0, delay: 0.5, damping: 1.0, velocity: 1.0)
		}
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
}
