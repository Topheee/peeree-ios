//
//  SetupViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 24.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class SetupViewController: PortraitImagePickerController, UITextFieldDelegate {
	@IBOutlet private var picButton: UIButton!
	@IBOutlet private var infoButton: UIButton!
	@IBOutlet private var launchAppButton: UIButton!
	@IBOutlet private var nameTextField: UITextField!
    @IBOutlet private var genderPicker: UISegmentedControl!
	
	@IBAction func finishIntroduction(sender: AnyObject) {
        guard let chosenName = nameTextField.text else { return }
        guard chosenName != "" else { return }
        
        NSUserDefaults.standardUserDefaults().setBool(true, forKey: AppDelegate.kPrefSkipOnboarding)
        
        UserPeerInfo.instance.peerName = chosenName
        UserPeerInfo.instance.gender = PeerInfo.Gender.values[genderPicker.selectedSegmentIndex]
        UserPeerInfo.instance.picture = picButton.imageForState(.Normal)
	}
	
	@IBAction func takePic(sender: UIButton) {
        showPicturePicker(NSLocalizedString("Omit portrait", comment: "Don't set a profile picture in onboarding")) { (action) in
            self.omitPicture()
        }
	}
	@IBAction func filledFirstname(sender: UITextField) {
		self.view.flyInSubviews([genderPicker], duration: 1.0, delay: 0.0, damping: 1.0, velocity: 1.0)
		UIView.animateWithDuration(1.0, delay: 1.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 1.0, options: UIViewAnimationOptions(rawValue: 0), animations: { () -> Void in
			self.launchAppButton.alpha = 1.0
			}, completion: nil)
	}
	
	override func viewDidLoad() {
        super.viewDidLoad()
        for view in [infoButton, picButton, nameTextField, genderPicker, launchAppButton] {
            view.alpha = 0.0
        }
		
		nameTextField.keyboardType = UIKeyboardType.NamePhonePad
	}
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        picButton.maskView = CircleMaskView(forView: picButton)
    }
	
	override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        guard picButton.imageForState(.Normal) == nil else { return }
        
        self.view.flyInSubviews([infoButton], duration: 1.0, delay: 0.0, damping: 1.0, velocity: 1.0)
        self.view.flyInSubviews([picButton], duration: 1.0, delay: 1.0, damping: 1.0, velocity: 1.0)
	}
    
    override func shouldPerformSegueWithIdentifier(identifier: String, sender: AnyObject?) -> Bool {
        if identifier == "finishOnboardingSegue" {
            return nameTextField.text != nil && nameTextField.text! != ""
        }
        return super.shouldPerformSegueWithIdentifier(identifier, sender: sender)
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        guard let rootTabBarController = segue.destinationViewController as? UITabBarController else { return }
        
        switch UserPeerInfo.instance.gender {
        case .Female:
            BrowseFilterSettings.sharedSettings.gender = .Male
        case .Male:
            BrowseFilterSettings.sharedSettings.gender = .Female
        default:
            BrowseFilterSettings.sharedSettings.gender = .Unspecified
        }
        
        rootTabBarController.selectedIndex = 1
    }
    
    func keyboardWillShow(notification: NSNotification) {
        guard let keyboardFrame = notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue else { return }
        
        let keyboardFrameRect = keyboardFrame.CGRectValue()
        
        var oldFrame = nameTextField.frame
        let textFieldsBottom = nameTextField.frame.origin.y + nameTextField.frame.height
        let keyboardTop = self.view.frame.height - keyboardFrameRect.size.height
        if textFieldsBottom > keyboardTop {
            dispatch_async(dispatch_get_main_queue(), {
                UIView.animateWithDuration(1.2, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.55, options: UIViewAnimationOptions.CurveEaseOut, animations: {
                    oldFrame.origin.y += keyboardTop - textFieldsBottom
                    self.nameTextField.frame = oldFrame
                }, completion: nil)
            })
        }
    }
    
    func keyboardWillHide(notification: NSNotification) {
        NSNotificationCenter.defaultCenter().removeObserver(self)
        nameTextField.setNeedsLayout()
    }
    
    // MARK - UITextFieldDelegate
	
    func textFieldShouldBeginEditing(textField: UITextField) -> Bool {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(keyboardWillShow), name: UIKeyboardDidShowNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(keyboardWillHide), name: UIKeyboardDidHideNotification, object: nil)
        return true
    }
    
	func textFieldShouldReturn(textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
    
    override func imagePickerControllerDidCancel(picker: UIImagePickerController) {
        super.imagePickerControllerDidCancel(picker)
        omitPicture()
    }
    
    override func pickedImage(image: UIImage) {
        picButton.setTitle("", forState: .Normal)
        picButton.setImage(image, forState: .Normal)
        dispatch_async(dispatch_get_main_queue()) {
            self.view.flyInSubviews([self.nameTextField], duration: 1.0, delay: 0.5, damping: 1.0, velocity: 1.0)
        }
    }
    
    private func omitPicture() {
        dispatch_async(dispatch_get_main_queue()) {
            self.view.flyInSubviews([self.nameTextField], duration: 1.0, delay: 0.5, damping: 1.0, velocity: 1.0)
        }
    }
}

/**
 *	Animates views like they are flown in from the bottom of the screen.
 *	@param views    the views to animate
 */
extension UIView {
	func flyInSubviews(views: [UIView], duration: NSTimeInterval, delay: NSTimeInterval, damping: CGFloat, velocity: CGFloat) {
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
