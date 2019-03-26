//
//  MainDataViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class MeViewController: PortraitImagePickerController, UITextFieldDelegate {
    @IBOutlet private weak var connectionNoteLabel: UILabel!
    @IBOutlet private weak var accountButton: UIButton!
    @IBOutlet private weak var accountIDLabel: UILabel!
    @IBOutlet private weak var mailTextField: UITextField!
    @IBOutlet private weak var mailNoteLabel: UILabel!
	@IBOutlet private weak var nameTextField: UITextField!
	@IBOutlet private weak var portraitImageButton: UIButton!
    @IBOutlet private weak var genderControl: UISegmentedControl!
    @IBOutlet private weak var birthdayInput: UITextField!
    @IBOutlet private weak var scrollView: UIScrollView!
    
    private var activeField: UITextField! = nil
    
	@IBAction func changeGender(_ sender: UISegmentedControl) {
        UserPeerInfo.instance.peer.gender = PeerInfo.Gender.allCases[sender.selectedSegmentIndex]
	}
    
    @IBAction func changePicture(_ sender: AnyObject) {
        showPicturePicker(true, destructiveActionName: NSLocalizedString("Delete Portrait", comment: "Button caption for removing the users portrait image"))
    }
    
    @IBAction func createDeleteAccount(_ sender: Any) {
        if AccountController.shared.accountExists {
            let alertController = UIAlertController(title: NSLocalizedString("Identity Deletion", comment: "Title message of alert for account deletion."), message: NSLocalizedString("This will delete your global Peeree identity and cannot be undone. All your pins as well as pins on you will be lost.", comment: "Message of account deletion alert."), preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Delete Identity", comment: "Caption of button"), style: .destructive, handler: { (button) in
                AccountController.shared.deleteAccount { (_ _error: Error?) in
                    self.restCompletion(_error) {
                        self.loadUserPeerInfo()
                    }
                }
                self.adjustAccountView()
            }))
            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
			alertController.addAction(cancelAction)
			alertController.preferredAction = cancelAction
            present(alertController, animated: true, completion: nil)
        } else {
			let createButtonTitle = NSLocalizedString("Create Identity", comment: "Caption of button.")
			let alertController = UIAlertController(title: NSLocalizedString("Agreement to Terms of Use", comment: "Title of identity creation alert"), message: String(format: NSLocalizedString("By tapping on '%@', you agree to our Terms of Use.", comment: "Message in identity creation alert."), createButtonTitle), preferredStyle: .actionSheet)
			let createAction = UIAlertAction(title: createButtonTitle, style: .`default`) { (action) in
				AccountController.shared.createAccount { (_ _error: Error?) in
					self.restCompletion(_error) {
						// we cannot go online immediately by now, as Me view would need to reload and probably for other reasons, too
						//                    PeeringController.shared.peering = true
					}
				}
				DispatchQueue.main.async {
					self.adjustAccountView()
				}
			}
			alertController.addAction(createAction)
			let viewTermsAction = UIAlertAction(title: NSLocalizedString("View Terms", comment: "Caption of identity creation alert action."), style: .`default`) { (action) in
				AppDelegate.viewTerms(in: self)
			}
			alertController.addAction(viewTermsAction)
			alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
			alertController.preferredAction = createAction
			alertController.present()
        }
    }
	
	@IBAction func browsePeereeURL(_ sender: Any) {
		UIApplication.shared.openURL(URL(string: wwwHomeURL)!)
	}
	
	@IBAction func browsePrivacyPolicyURL(_ sender: Any) {
		UIApplication.shared.openURL(URL(string: wwwPrivacyPolicyURL)!)
	}
	
    private func fillBirthdayInput(with date: Date) {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .none
        dateFormatter.dateStyle = .long
        birthdayInput.text = dateFormatter.string(from: date)
    }
    
    @objc func agePickerChanged(_ sender: UIDatePicker) {
        fillBirthdayInput(with: sender.date)
    }
    
    @objc func ageConfirmed(_ sender: UIBarButtonItem) {
        birthdayInput.resignFirstResponder()
    }
    
    @objc func ageOmitted(_ sender: UIBarButtonItem) {
        birthdayInput.text = nil
        birthdayInput.resignFirstResponder()
    }
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if let personDetailVC = segue.destination as? PersonDetailViewController {
            personDetailVC.displayedPeerInfo = UserPeerInfo.instance.peer
        } else if let charTraitVC = segue.destination as? CharacterTraitViewController {
			charTraitVC.characterTraits = UserPeerInfo.instance.peer.characterTraits
            charTraitVC.userTraits = true
		}
	}
	
	override func viewDidLoad() {
        super.viewDidLoad()
        registerForKeyboardNotifications()
        _ = PeeringController.Notifications.connectionChangedState.addObserver { [weak self] notification in
            self?.lockView()
        }
	}
	
	override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
		loadUserPeerInfo()
        adjustAccountView()
		lockView()
	}
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        _ = CircleMaskView(maskedView: portraitImageButton.imageView!)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
	
	// MARK: UITextFieldDelegate
	
	func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
		guard textField == birthdayInput else { return true }
		
		let today = Date()
		let datePicker = UIDatePicker()
		datePicker.datePickerMode = .date
		var minComponents = Calendar.current.dateComponents([.day, .month, .year], from: today)
		minComponents.year = minComponents.year! - PeerInfo.MaxAge
		var maxComponents = Calendar.current.dateComponents([.day, .month, .year], from: today)
		maxComponents.year = maxComponents.year! - PeerInfo.MinAge
		
		datePicker.minimumDate = Calendar.current.date(from: minComponents)
		datePicker.maximumDate = Calendar.current.date(from: maxComponents)
		
		datePicker.date = UserPeerInfo.instance.dateOfBirth ?? datePicker.maximumDate ?? today
		datePicker.addTarget(self, action: #selector(agePickerChanged), for: .valueChanged)
		
		let saveToolBar = UIToolbar()
		let omitButton = UIBarButtonItem(title: NSLocalizedString("Omit", comment: ""), style: .plain, target: self, action: #selector(ageOmitted))
		let spaceButton = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
		let doneButton = UIBarButtonItem(title: NSLocalizedString("Done", comment: ""), style: .done, target: self, action: #selector(ageConfirmed))
		
		spaceButton.title = birthdayInput.placeholder
		omitButton.tintColor = UIColor.red
		saveToolBar.isTranslucent = true
		saveToolBar.sizeToFit()
		saveToolBar.setItems([omitButton,spaceButton,doneButton], animated: false)
		saveToolBar.isUserInteractionEnabled = true
		
		birthdayInput.inputView = datePicker
		birthdayInput.inputAccessoryView = saveToolBar
		
		return true
	}
	
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        activeField = nil
        switch textField {
        case nameTextField:
            guard let newValue = textField.text, newValue != "" else {
                textField.text = UserPeerInfo.instance.peer.nickname
                return
            }
            let endIndex = newValue.index(newValue.startIndex, offsetBy: PeerInfo.MaxNicknameSize, limitedBy: newValue.endIndex) ?? newValue.endIndex
            UserPeerInfo.instance.peer.nickname = String(newValue[..<endIndex])
        case birthdayInput:
            guard textField.text != nil && textField.text != "" else {
                UserPeerInfo.instance.dateOfBirth = nil
                return
            }
            guard let datePicker = textField.inputView as? UIDatePicker else { return }
            UserPeerInfo.instance.dateOfBirth = datePicker.date
        case mailTextField:
            guard textField.text ?? "" != AccountController.shared.accountEmail ?? "" else { return }
            guard let newValue = textField.text, newValue != "" else {
                AccountController.shared.deleteEmail { _error in
                    self.restCompletion(_error) {}
                }
                return
            }
            
            let endIndex = newValue.index(newValue.startIndex, offsetBy: PeerInfo.MaxEmailSize, limitedBy: newValue.endIndex) ?? newValue.endIndex
            AccountController.shared.update(email: String(newValue[..<endIndex])) { _error in
                self.restCompletion(_error) {}
            }
        default:
            break
        }
        
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard textField == nameTextField || textField == mailTextField else { return true }
        
        if (range.length + range.location > textField.text!.utf8.count) {
            return false
        }
        
        let newLength = textField.text!.utf8.count + string.utf8.count - range.length
        return textField == nameTextField ? newLength <= PeerInfo.MaxNicknameSize : newLength <= PeerInfo.MaxEmailSize
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        activeField = textField
    }
	
	// MARK: Private Methods
    
    override func picked(image: UIImage?) {
        super.picked(image: image)
        portraitImageButton.setImage(image ?? #imageLiteral(resourceName: "PortraitUnavailable"), for: [])
        if #available(iOS 11.0, *) {
            portraitImageButton.accessibilityIgnoresInvertColors = image != nil
        }
    }
    
    private func loadUserPeerInfo() {
        nameTextField.text = UserPeerInfo.instance.peer.nickname
        genderControl.selectedSegmentIndex = PeerInfo.Gender.allCases.index(of: UserPeerInfo.instance.peer.gender) ?? 0
        if let date = UserPeerInfo.instance.dateOfBirth {
            fillBirthdayInput(with: date)
        } else {
            birthdayInput.text = nil
        }
        portraitImageButton.setImage(UserPeerInfo.instance.picture ?? #imageLiteral(resourceName: "PortraitUnavailable"), for: [])
        if #available(iOS 11.0, *) {
            portraitImageButton.accessibilityIgnoresInvertColors = UserPeerInfo.instance.picture != nil
        }
    }
    
    private func registerForKeyboardNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWasShown), name: NSNotification.Name.UIKeyboardDidShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillBeHidden), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }
    
    /// Called when the UIKeyboardDidShowNotification is sent.
    @objc private func keyboardWasShown(aNotification: Notification) {
        guard let info = aNotification.userInfo else { return }
		
		// TODO iOS 11 bug: we do only need to add the accessory height on our own, if the navigation bar is NOT collapsed
		// TEST with iOS < 11
		let accessoryHeight = activeField.inputView?.inputAccessoryView?.frame.height ?? 0.0
        let inputHeight = (info[UIKeyboardFrameBeginUserInfoKey] as! CGRect).height
		let keyboardHeight = accessoryHeight + inputHeight

        let contentInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: keyboardHeight, right: 0.0)
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
        
        // If active text field is hidden by keyboard, scroll it so it's visible
        var aRect = self.view.frame
        aRect.size.height -= keyboardHeight
        if (!aRect.contains(activeField.frame.origin) ) {
            scrollView.scrollRectToVisible(activeField.frame, animated: true)
        }
    }
    
    /// Called when the UIKeyboardWillHideNotification is sent
    @objc private func keyboardWillBeHidden(aNotification: Notification) {
        let contentInsets = UIEdgeInsets.zero
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
    }
    
    private func restCompletion(_ _error: Error?, noErrorAction: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.adjustAccountView()
            
            if let error = _error {
                AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Connection Error", comment: "Standard title message of alert for internet connection errors."))
            } else {
                noErrorAction()
            }
        }
    }
    
    private func adjustAccountView() {
        if AccountController.shared.accountExists {
            accountButton.setTitle(NSLocalizedString("Delete Identity", comment: "Caption of button"), for: .normal)
            accountButton.tintColor = .red
            mailTextField.text = AccountController.shared.accountEmail
            accountIDLabel.text = AccountController.shared.getPeerID()
        } else {
            accountButton.setTitle(NSLocalizedString("Create Identity", comment: "Caption of button"), for: .normal)
            accountButton.tintColor = AppDelegate.shared.theme.globalTintColor
        }
        mailTextField.isHidden = !AccountController.shared.accountExists
        mailNoteLabel.isHidden = !AccountController.shared.accountExists
        accountIDLabel.isHidden = !AccountController.shared.accountExists
        accountButton.isEnabled = !(AccountController.shared.isCreatingAccount || AccountController.shared.isDeletingAccount)
    }
    
    /// do not allow changes to UserPeerInfo while peering
    private func lockView() {
        for control: UIControl in [nameTextField, portraitImageButton, genderControl, birthdayInput] {
            control.isEnabled = !PeeringController.shared.peering
        }
        connectionNoteLabel.isHidden = !PeeringController.shared.peering
    }
}
