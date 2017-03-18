//
//  WelcomeViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 12.10.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import UIKit

final class WelcomeViewController: UIViewController {
	@IBOutlet private weak var infoButton: UIButton!
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let vc = segue.destination as? OnboardingDescriptionViewController else { return }
        
        vc.infoType = .general
    }
	
	override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        infoButton.tintColor = AppDelegate.shared.theme.globalTintColor // for whatever reason we have to do that here...
		if !animated {
			//at the very first showing, the view appears unanimated, so only here we want to show the animation
			self.view.flyInSubviews([infoButton], duration: 2.0, delay: 0.5, damping: 1.0, velocity: 1.0)
		}
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
}
