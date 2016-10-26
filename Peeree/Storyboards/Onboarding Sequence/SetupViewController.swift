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
    
    var nameTextFieldFrame: CGRect?
	
	@IBAction func finishIntroduction(_ sender: AnyObject) {
        guard let chosenName = nameTextField.text else { return }
        guard chosenName != "" else { return }
        
        UserPeerInfo.instance.peerName = chosenName
        UserPeerInfo.instance.gender = PeerInfo.Gender.values[genderPicker.selectedSegmentIndex]
        UserPeerInfo.instance.picture = picButton.image(for: UIControlState())
        
        AppDelegate.sharedDelegate.finishIntroduction()
	}
	
	@IBAction func takePic(_ sender: UIButton) {
        guard !nameTextField.isFirstResponder else { return }
        
        picButton.layer.removeAllAnimations()
        picButton.alpha = 1.0
        showPicturePicker(destructiveActionName: NSLocalizedString("Omit Portrait", comment: "Don't set a profile picture during onboarding.")) { (action) in
            self.pickedImage(UIImage(named: "PortraitUnavailable")!)
        }
	}
	@IBAction func filledFirstname(_ sender: UITextField) {
		self.view.flyInSubviews([genderPicker], duration: 1.0, delay: 0.5, damping: 1.0, velocity: 1.0)
		UIView.animate(withDuration: 1.0, delay: 1.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 1.0, options: [], animations: { () -> Void in
			self.launchAppButton.alpha = 1.0
        }, completion: { finished in
            UIView.animate(withDuration: 0.5, delay: 1.2, usingSpringWithDamping: 1.0, initialSpringVelocity: 3.0, options: [.repeat, .autoreverse, .allowUserInteraction], animations: { () -> Void in
                self.launchAppButton.transform = self.launchAppButton.transform.scaledBy(x: 0.97, y: 0.97)
            }, completion: nil)
        })
    }
	
	override func viewDidLoad() {
        super.viewDidLoad()
        for view in [infoButton, picButton, nameTextField, genderPicker, launchAppButton] as [UIView] {
            view.alpha = 0.0
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        _ = CircleMaskView(maskedView: picButton.imageView!)
    }
	
	override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard nameTextField.alpha == 0.0 else { return }
        
        self.view.flyInSubviews([infoButton], duration: 1.0, delay: 0.0, damping: 1.0, velocity: 1.0)
        self.view.flyInSubviews([picButton], duration: 1.0, delay: 1.0, damping: 1.0, velocity: 1.0)
        UIView.animate(withDuration: 1.0, delay: 7.0, options: [.repeat, .autoreverse, .allowUserInteraction], animations: {
            self.picButton.alpha = 0.6
        }, completion: nil)
	}
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if identifier == "finishOnboardingSegue" {
            return nameTextField.text != nil && nameTextField.text != ""
        }
        return super.shouldPerformSegue(withIdentifier: identifier, sender: sender)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let rootTabBarController = segue.destination as? UITabBarController else {
            guard let vc = segue.destination as? OnboardingDescriptionViewController else { return }
            
            vc.infoType = .data
            return
        }
        
        switch UserPeerInfo.instance.gender {
        case .Female:
            BrowseFilterSettings.sharedSettings.gender = .male
        case .Male:
            BrowseFilterSettings.sharedSettings.gender = .female
        default:
            BrowseFilterSettings.sharedSettings.gender = .unspecified
        }
        
        rootTabBarController.selectedIndex = 1
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue else { return }
        
        let keyboardFrameRect = keyboardFrame.cgRectValue
        
        nameTextFieldFrame = nameTextField.frame
        var newFrame = nameTextFieldFrame!
        let textFieldsBottom = nameTextField.frame.origin.y + nameTextField.frame.height
        let keyboardTop = self.view.frame.height - keyboardFrameRect.size.height
        if textFieldsBottom > keyboardTop {
            DispatchQueue.main.async(execute: {
                UIView.animate(withDuration: 1.2, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.55, options: UIViewAnimationOptions.curveEaseOut, animations: {
                    newFrame.origin.y += keyboardTop - textFieldsBottom
                    self.nameTextField.frame = newFrame
                }, completion: nil)
            })
        }
    }
    
    func keyboardWillHide(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK - UITextFieldDelegate
	
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: NSNotification.Name.UIKeyboardDidShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: NSNotification.Name.UIKeyboardDidHide, object: nil)
        return true
    }
    
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
		return true
	}
    
    override func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        super.imagePickerControllerDidCancel(picker)
        pickedImage(UIImage(named: "PortraitUnavailable")!)
    }
    
    override func pickedImage(_ image: UIImage) {
        picButton.setImage(image, for: UIControlState())
        DispatchQueue.main.async {
            self.view.flyInSubviews([self.nameTextField], duration: 1.0, delay: 0.5, damping: 1.0, velocity: 1.0)
        }
    }
}

/**
 *	Animates views like they are flown in from the bottom of the screen.
 *	@param views    the views to animate
 */
extension UIView {
	func flyInSubviews(_ views: [UIView], duration: TimeInterval, delay: TimeInterval, damping: CGFloat, velocity: CGFloat) {
		var positions = [CGRect]()
		for value in views {
			positions.append(value.frame)
			value.frame.origin.y = self.frame.height
			value.alpha = 0.0
		}
		
		UIView.animate(withDuration: duration, delay: delay, usingSpringWithDamping: damping, initialSpringVelocity: velocity, options: UIViewAnimationOptions(rawValue: 0), animations: { () -> Void in
		for (index, view) in views.enumerated() {
			view.frame = positions[index]
			view.alpha = 1.0
		}
		}, completion: nil)
	}
}
