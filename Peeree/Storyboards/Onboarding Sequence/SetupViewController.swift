//
//  SetupViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 24.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class SetupViewController: UIViewController {
	
	@IBAction func finishIntroduction(sender: AnyObject) {
		let defs = NSUserDefaults.standardUserDefaults()
		defs.setBool(true, forKey: AppDelegate.kPrefFirstLaunch)
		let storyboard = UIStoryboard(name:"Main", bundle: nil)
		self.showViewController(storyboard.instantiateInitialViewController() as! UIViewController, sender: self)
	}
}