//
//  SetupViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 24.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class SetupViewController: PortraitImagePickerController, UITextFieldDelegate {
	@IBOutlet private weak var picButton: UIButton!
	@IBOutlet private weak var infoButton: UIButton!
	@IBOutlet private weak var launchAppButton: UIButton!
	@IBOutlet private weak var nameTextField: UITextField!
    @IBOutlet private weak var genderPicker: UISegmentedControl!
    @IBOutlet private weak var pickPicButton: UIButton!
    
    /// frame after keyboard animation
    private var nameTextFieldAdjustedFrame: CGRect = .zero
    /// frame before keyboard animation
    private var nameTextFieldOriginalFrame: CGRect = .zero
    private var keyboardActive = false
    
	@IBAction func finishIntroduction(_ sender: AnyObject) {
        guard let chosenName = nameTextField.text, chosenName != "" else { return }
        
        AccountController.shared.createAccount { (_error) in
            if let error = _error {
                // we do not inform the user about this as we initiated it silently
                NSLog("Error creating account: \(error)")
            }
        }
        
        UserPeerInfo.instance.peer.nickname = chosenName
        UserPeerInfo.instance.peer.gender = PeerInfo.Gender.values[genderPicker.selectedSegmentIndex]
        
        switch UserPeerInfo.instance.peer.gender {
        case .female:
            BrowseFilterSettings.shared.gender = .male
        case .male:
            BrowseFilterSettings.shared.gender = .female
        default:
            BrowseFilterSettings.shared.gender = .unspecified
        }
        
        AppDelegate.shared.finishIntroduction()
        dismiss(animated: true, completion: nil)
	}
	
	@IBAction func takePic(_ sender: UIButton) {
        guard !nameTextField.isFirstResponder else { return }
        
        showPicturePicker(destructiveActionName: NSLocalizedString("Omit Portrait", comment: "Don't set a profile picture during onboarding."))
	}
    
	@IBAction func filledFirstname(_ sender: UITextField) {
        launchAppButton.layer.removeAllAnimations()
        launchAppButton.transform = CGAffineTransform.identity
		UIView.animate(withDuration: 1.0, delay: 0.8, usingSpringWithDamping: 1.0, initialSpringVelocity: 1.0, options: [], animations: { () -> Void in
			self.launchAppButton.alpha = 1.0
        }, completion: { finished in
            UIView.animate(withDuration: 0.5, delay: 1.2, usingSpringWithDamping: 1.0, initialSpringVelocity: 3.0, options: [.repeat, .autoreverse, .allowUserInteraction], animations: { () -> Void in
                self.launchAppButton.transform = self.launchAppButton.transform.scaledBy(x: 0.97, y: 0.97)
            }, completion: nil)
        })
    }
	
	override func viewDidLoad() {
        super.viewDidLoad()
        launchAppButton.alpha = 0.0
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: NSNotification.Name.UIKeyboardDidShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide), name: NSNotification.Name.UIKeyboardDidHide, object: nil)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if picButton.mask == nil {
            _ = CircleMaskView(maskedView: picButton.imageView!)
        }
        if #available(iOS 11, *) {
            // iOS 11 seems to layout subviews every time a character is typed in UITextField
            if keyboardActive {
                // set frame back to position above keyboard (after animation)
                nameTextField.frame = nameTextFieldAdjustedFrame
            }
        }
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
        
        rootTabBarController.selectedIndex = 1
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    override func picked(image: UIImage?) {
        super.picked(image: image)
        picButton.setImage(image ?? #imageLiteral(resourceName: "PortraitUnavailable"), for: [])
        if #available(iOS 11.0, *) {
            picButton.accessibilityIgnoresInvertColors = image != nil
        }
        pickPicButton.isHidden = true
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue else { return }
        
        keyboardActive = true
        let keyboardFrameRect = keyboardFrame.cgRectValue
        
        var newFrame = nameTextField.frame
        nameTextFieldOriginalFrame = newFrame
        let textFieldsBottom = newFrame.origin.y + newFrame.height
        let keyboardTop = self.view.frame.height - keyboardFrameRect.size.height
        newFrame.origin.y += keyboardTop - textFieldsBottom
        nameTextFieldAdjustedFrame = newFrame
        if textFieldsBottom > keyboardTop {
            DispatchQueue.main.async(execute: {
                UIView.animate(withDuration: 1.2, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.55, options: UIViewAnimationOptions.curveEaseOut, animations: {
                    self.nameTextField.frame = newFrame
                }, completion: nil)
            })
        }
    }
    
    @objc func keyboardDidHide(_ notification: Notification) {
        keyboardActive = false
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.6, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.55, options: UIViewAnimationOptions.curveEaseOut, animations: {
                self.nameTextField.frame = self.nameTextFieldOriginalFrame
            }, completion: { (completed) in
                self.view.setNeedsLayout()
            })
        }
    }
    
    // MARK: UITextFieldDelegate
    
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
		return true
	}
}
