//
//  SetupViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 24.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class SetupViewController: UIViewController, UITextFieldDelegate {
	@IBOutlet var picButton: UIButton!
	@IBOutlet var infoButton: UIButton!
	@IBOutlet var launchAppButton: UIButton!
	@IBOutlet var firstnameTextField: UITextField!
	@IBOutlet var lastnameTextField: UITextField!
	@IBOutlet var genderPicker: UISegmentedControl!
	
	@IBAction func finishIntroduction(sender: AnyObject) {
		let defs = NSUserDefaults.standardUserDefaults()
		defs.setBool(true, forKey: AppDelegate.kPrefFirstLaunch)
		//let storyboard = UIStoryboard(name:"Main", bundle: nil)
		//self.showViewController(storyboard.instantiateInitialViewController()!, sender: self)
	}
	
	@IBAction func takePic(sender: UIButton) {
		//TODO the user is now asked to take or choose a picture of him- or herself
		self.view.flyInViews([firstnameTextField, lastnameTextField], duration: 1.0, delay: 0.0, damping: 1.0, velocity: 1.0)
	}
	@IBAction func filledFirstname(sender: UITextField) {
		self.view.flyInViews([genderPicker], duration: 1.0, delay: 0.0, damping: 1.0, velocity: 1.0)
		UIView.animateWithDuration(1.0, delay: 1.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 1.0, options: UIViewAnimationOptions(rawValue: 0), animations: { () -> Void in
			self.launchAppButton.alpha = 1.0
			}, completion: nil)
	}
	
	override func viewDidLoad() {
		infoButton.alpha = 0.0
		picButton.alpha = 0.0
		firstnameTextField.alpha = 0.0
		lastnameTextField.alpha = 0.0
		genderPicker.alpha = 0.0
		launchAppButton.alpha = 0.0
		
		firstnameTextField.keyboardType = UIKeyboardType.NamePhonePad
		lastnameTextField.keyboardType = UIKeyboardType.NamePhonePad
		
	}
	
	override func viewDidAppear(animated: Bool) {
		self.view.flyInViews([infoButton], duration: 1.0, delay: 0.0, damping: 1.0, velocity: 1.0)
		self.view.flyInViews([picButton], duration: 1.0, delay: 0.7, damping: 1.0, velocity: 1.0)
	}
	
	func textFieldShouldReturn(textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
}

extension UIView {
	func flyInViews(views: [UIView], duration: NSTimeInterval, delay: NSTimeInterval, damping: CGFloat, velocity: CGFloat) {
		
		var positions = [CGRect]()
		for value in views {
			positions.append(value.frame)
			value.frame.origin.y = self.frame.height
			value.alpha = 0.0
		}
		
		UIView.animateWithDuration(duration, delay: delay, usingSpringWithDamping: damping, initialSpringVelocity: velocity, options: UIViewAnimationOptions(rawValue: 0), animations: { () -> Void in
		for (index, view) in views.enumerate() {
			view.frame = positions[index]
			view.alpha = 1.0
		}
		}, completion: nil)
	}
}
