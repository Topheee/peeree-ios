//
//  MainDataViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class MeViewController: PortraitImagePickerController, UITextFieldDelegate {
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
    
    private var restCompletion: (_ _error: Error?) -> Void {
        return { [weak self] (_error: Error?) in
            DispatchQueue.main.async {
                self?.adjustAccountView()
            }
            
            guard let error = _error else { return }
            
            AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Connection Error", comment: "Standard title message of alert for internet connection errors."))
        }
    }
    
	@IBAction func changeGender(_ sender: UISegmentedControl) {
        UserPeerInfo.instance.peer.gender = PeerInfo.Gender.values[sender.selectedSegmentIndex]
	}
    
    @IBAction func changePicture(_ sender: AnyObject) {
        showPicturePicker(true, destructiveActionName: NSLocalizedString("Delete Portrait", comment: "Button caption for removing the users portrait image"))
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
    
    @IBAction func createDeleteAccount(_ sender: Any) {
        if AccountController.shared.accountExists {
            let alertController = UIAlertController(title: NSLocalizedString("Identity Deletion", comment: "Title message of alert for account deletion."), message: NSLocalizedString("This will delete your global Peeree identity and cannot be undone. All your pins and purchases will be lost.", comment: "Message of account deletion alert."), preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Delete Identity", comment: "Caption of button"), style: .destructive, handler: { (button) in
                AccountController.shared.deleteAccount { (_ _error: Error?) in
                    self.restCompletion(_error)
                    guard _error == nil else { return }
                    DispatchQueue.main.async {
                        self.loadUserPeerInfo()
                    }
                }
                self.adjustAccountView()
            }))
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
            present(alertController, animated: true, completion: nil)
        } else {
            AccountController.shared.createAccount(completion: restCompletion)
            adjustAccountView()
        }
    }
    
    private func fillBirthdayInput(with date: Date) {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .none
        dateFormatter.dateStyle = .long
        birthdayInput.text = dateFormatter.string(from: date)
    }
    
    func agePickerChanged(_ sender: UIDatePicker) {
        fillBirthdayInput(with: sender.date)
    }
    
    func ageConfirmed(_ sender: UIBarButtonItem) {
        birthdayInput.resignFirstResponder()
    }
    
    func ageOmitted(_ sender: UIBarButtonItem) {
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
        birthdayInput.delegate = self
        
        registerForKeyboardNotifications()
	}
	
	override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
		loadUserPeerInfo()
        adjustAccountView()
	}
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        _ = CircleMaskView(maskedView: portraitImageButton.imageView!)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
	
	// MARK: UITextFieldDelegate
	
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
            UserPeerInfo.instance.peer.nickname = newValue.substring(to: endIndex)
        case birthdayInput:
            guard textField.text != nil && textField.text != "" else {
                UserPeerInfo.instance.dateOfBirth = nil
                return
            }
            guard let datePicker = textField.inputView as? UIDatePicker else { return }
            UserPeerInfo.instance.dateOfBirth = datePicker.date
        case mailTextField:
            guard textField.text != AccountController.shared.accountEmail else { return }
            guard let newValue = textField.text, newValue != "" else {
                AccountController.shared.deleteEmail(completion: restCompletion)
                return
            }
            
            let endIndex = newValue.index(newValue.startIndex, offsetBy: PeerInfo.MaxEmailSize, limitedBy: newValue.endIndex) ?? newValue.endIndex
            AccountController.shared.update(email: newValue.substring(to: endIndex), completion: restCompletion)
        default:
            break
        }
        
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard textField == nameTextField || textField == mailTextField else { return true }
        
        if (range.length + range.location > textField.text!.characters.count) {
            return false
        }
        
        let newLength = textField.text!.characters.count + string.characters.count - range.length
        return textField == nameTextField ? newLength <= PeerInfo.MaxNicknameSize : newLength <= PeerInfo.MaxEmailSize
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        activeField = textField
    }
    
    override func picked(image: UIImage?) {
        super.picked(image: image)
        portraitImageButton.setImage(image ?? #imageLiteral(resourceName: "PortraitUnavailable"), for: UIControlState())
    }
    
    private func loadUserPeerInfo() {
        nameTextField.text = UserPeerInfo.instance.peer.nickname
        genderControl.selectedSegmentIndex = PeerInfo.Gender.values.index(of: UserPeerInfo.instance.peer.gender) ?? 0
        if let date = UserPeerInfo.instance.dateOfBirth {
            fillBirthdayInput(with: date)
        } else {
            birthdayInput.text = nil
        }
        portraitImageButton.setImage(UserPeerInfo.instance.picture ?? #imageLiteral(resourceName: "PortraitUnavailable"), for: UIControlState())
    }
    
    func registerForKeyboardNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWasShown), name: NSNotification.Name.UIKeyboardDidShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillBeHidden), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }
    
    /// Called when the UIKeyboardDidShowNotification is sent.
    @objc func keyboardWasShown(aNotification: Notification) {
        guard let info = aNotification.userInfo else { return }
        
        let kbSize = (info[UIKeyboardFrameBeginUserInfoKey] as! CGRect).size
        
        let contentInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: kbSize.height, right: 0.0)
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
        
        // If active text field is hidden by keyboard, scroll it so it's visible
        var aRect = self.view.frame
        aRect.size.height -= kbSize.height
        if (!aRect.contains(activeField.frame.origin) ) {
            scrollView.scrollRectToVisible(activeField.frame, animated: true)
        }
    }
    
    /// Called when the UIKeyboardWillHideNotification is sent
    func keyboardWillBeHidden(aNotification: Notification) {
        let contentInsets = UIEdgeInsets.zero
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
    }
}
