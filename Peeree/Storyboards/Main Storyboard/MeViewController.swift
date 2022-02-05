//
//  MainDataViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

/// Displays and edits the users peer info data, as well as their Peeree identity.
final class MeViewController: UIViewController, UITextFieldDelegate, UITextViewDelegate, PortraitImagePickerControllerDelegate {
	@IBOutlet private weak var previewButton: UIBarButtonItem!
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
	@IBOutlet private weak var bioTextView: UITextView!

	private var activeField: (view: UIView, inputView: UIView?)? = nil
	private var connectionStateObserver: NSObjectProtocol? = nil
	private let portraitImagePicker = PortraitImagePickerController()
	
	@IBAction func changeGender(_ sender: UISegmentedControl) {
		let gender = PeerInfo.Gender.allCases[sender.selectedSegmentIndex]
		modifyUserInfo { info in
			info.gender = gender
		}
	}
	
	@IBAction func changePicture(_ sender: AnyObject) {
		portraitImagePicker.delegate = self
		portraitImagePicker.showPicturePicker(allowCancel: true, destructiveActionName: NSLocalizedString("Delete Portrait", comment: "Button caption for removing the users portrait image"))
	}

	private func deleteServerChatAccount() {
		ServerChatController.withInstance { _serverChatController in
			guard let serverChatController = _serverChatController else { return }

			serverChatController.deleteAccount { _error in
				if let error = _error {
					InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Server Chat Account Deletion Failed", comment: "Title of in-app alert."))
					try? ServerChatController.removePasswordFromKeychain()
				}
			}
		}
	}

	private func initiateDeleteAccount() {
		let alertController = UIAlertController(title: NSLocalizedString("Identity Deletion", comment: "Title message of alert for account deletion."), message: NSLocalizedString("This will delete your global Peeree identity and cannot be undone. All your pins as well as pins on you will be lost.", comment: "Message of account deletion alert."), preferredStyle: .alert)
		alertController.addAction(UIAlertAction(title: NSLocalizedString("Delete Identity", comment: "Caption of button"), style: .destructive, handler: { (button) in
			PeeringController.shared.peering = false
			self.deleteServerChatAccount()
			AccountController.shared.deleteAccount { (_ _error: Error?) in
				self.accountActionCompletionHandler(_error) {}
			}
			self.adjustAccountView()
		}))
		let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
		alertController.addAction(cancelAction)
		alertController.preferredAction = cancelAction
		present(alertController, animated: true, completion: nil)
	}

	private func initiateCreateAccount() {
		let createButtonTitle = NSLocalizedString("Create Identity", comment: "Caption of button.")
		let alertController = UIAlertController(title: NSLocalizedString("Agreement to Terms of Use", comment: "Title of identity creation alert"), message: String(format: NSLocalizedString("By tapping on '%@', you agree to our Terms of Use.", comment: "Message in identity creation alert."), createButtonTitle), preferredStyle: UIDevice.current.iPadOrMac ? .alert : .actionSheet)
		let createAction = UIAlertAction(title: createButtonTitle, style: .`default`) { (action) in
			AccountController.shared.createAccount { (_ _error: Error?) in
				self.accountActionCompletionHandler(_error) {
					// we cannot go online immediately by now, as Me view would need to reload and probably for other reasons, too
					//					PeeringController.shared.peering = true
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

	@IBAction func createDeleteAccount(_ sender: Any) {
		if AccountController.shared.accountExists {
			initiateDeleteAccount()
		} else {
			initiateCreateAccount()
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

	@objc func bioConfirmed(_ sender: UIBarButtonItem) {
		bioTextView.resignFirstResponder()
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: sender)
		if let personDetailVC = segue.destination as? PersonDetailViewController {
			personDetailVC.peerID = AccountController.shared.peerID
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		registerForKeyboardNotifications()
		connectionStateObserver = PeeringController.Notifications.connectionChangedState.addObserver { [weak self] notification in
			self?.lockAndLoadView()
		}
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		adjustAccountView()
		lockAndLoadView()
		navigationController?.isToolbarHidden = true
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		bioTextView.resignFirstResponder()
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		_ = CircleMaskView(maskedView: portraitImageButton.imageView!)
	}
	
	deinit {
		connectionStateObserver.map { NotificationCenter.default.removeObserver($0) }
		NotificationCenter.default.removeObserver(self)
	}
	
	// MARK: UITextFieldDelegate
	
	func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
		guard textField == birthdayInput else { return true }
		
		let today = Date()
		let datePicker = UIDatePicker()
		datePicker.datePickerMode = .date
		if #available(iOS 13.4, *) {
			datePicker.preferredDatePickerStyle = .wheels
		}
		var minComponents = Calendar.current.dateComponents([.day, .month, .year], from: today)
		minComponents.year = minComponents.year! - PeerInfo.MaxAge
		var maxComponents = Calendar.current.dateComponents([.day, .month, .year], from: today)
		maxComponents.year = maxComponents.year! - PeerInfo.MinAge
		
		datePicker.minimumDate = Calendar.current.date(from: minComponents)
		datePicker.maximumDate = Calendar.current.date(from: maxComponents)

		UserPeer.instance.read { _, birthday, _, _ in
			datePicker.date = birthday ?? datePicker.maximumDate ?? today
			datePicker.addTarget(self, action: #selector(self.agePickerChanged), for: .valueChanged)
		}
		
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
				UserPeer.instance.read { info, _, _, _ in
					textField.text = info?.nickname
				}
				return
			}
			let endIndex = newValue.index(newValue.startIndex, offsetBy: PeerInfo.MaxNicknameSize, limitedBy: newValue.endIndex) ?? newValue.endIndex
			modifyUserInfo { info in
				info.nickname = String(newValue[..<endIndex])
			}
		case birthdayInput:
			guard textField.text != nil && textField.text != "" else {
				UserPeer.instance.modify(birthday: nil)
				return
			}
			guard let datePicker = textField.inputView as? UIDatePicker else { return }
			UserPeer.instance.modify(birthday: datePicker.date)
		case mailTextField:
			guard textField.text ?? "" != AccountController.shared.accountEmail ?? "" else { return }
			guard let newValue = textField.text, newValue != "" else {
				AccountController.shared.deleteEmail { _error in
					self.accountActionCompletionHandler(_error) {}
				}
				return
			}
			
			let endIndex = newValue.index(newValue.startIndex, offsetBy: PeerInfo.MaxEmailSize, limitedBy: newValue.endIndex) ?? newValue.endIndex
			AccountController.shared.update(email: String(newValue[..<endIndex])) { _error in
				self.accountActionCompletionHandler(_error) {}
			}
		default:
			break
		}
		
	}
	
	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		guard textField == nameTextField || textField == mailTextField else { return true }
		
		return textField.allowChangeCharacters(in: range, replacementString: string, maxUtf8Length: textField == nameTextField ? PeerInfo.MaxNicknameSize : PeerInfo.MaxEmailSize)
	}
	
	func textFieldDidBeginEditing(_ textField: UITextField) {
		activeField = (textField, textField.inputView)
	}

	// MARK: UITextViewDelegate

	func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
		if let font = textView.font {
			let descriptor = font.fontDescriptor
			if let newDescriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.subtracting(UIFontDescriptor.SymbolicTraits.traitItalic)) {
				textView.font = UIFont(descriptor: newDescriptor, size: 0.0)
			}
		}

		let saveToolBar = UIToolbar()
		let spaceButton = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
		let doneButton = UIBarButtonItem(title: NSLocalizedString("Done", comment: ""), style: .done, target: self, action: #selector(bioConfirmed))

		saveToolBar.isTranslucent = true
		saveToolBar.sizeToFit()
		saveToolBar.setItems([spaceButton,doneButton], animated: false)
		saveToolBar.isUserInteractionEnabled = true

		textView.inputAccessoryView = saveToolBar
		activeField = (textView, textView.inputView)
		return true
	}

	func textViewDidEndEditing(_ textView: UITextView) {
		UserPeer.instance.modify(biography: textView.text)
		activeField = nil
	}

	func viewControllerToPresentImagePicker() -> UIViewController {
		return self
	}

	func picked(image: UIImage?) {
		portraitImageButton.setImage(image ?? #imageLiteral(resourceName: "PortraitUnavailable"), for: [])
		if #available(iOS 11.0, *) {
			portraitImageButton.accessibilityIgnoresInvertColors = image != nil
		}
	}

	// MARK: - Private

	// MARK: Methods

	private func loadUserPeerInfo(peerInfo: PeerInfo?, birthday: Date?, portrait: CGImage?, bio: String) {
		nameTextField.text = peerInfo?.nickname
		genderControl.selectedSegmentIndex = PeerInfo.Gender.allCases.firstIndex(of: peerInfo?.gender ?? .queer) ?? 0
		if let date = birthday {
			fillBirthdayInput(with: date)
		} else {
			birthdayInput.text = nil
		}
		picked(image: portrait.map { UIImage(cgImage: $0) })
		if bio != "" {
			bioTextView.text = bio
		} else if let font = bioTextView.font {
			bioTextView.text = nil
			let descriptor = font.fontDescriptor
			if let newDescriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(UIFontDescriptor.SymbolicTraits.traitItalic)) {
				bioTextView.font = UIFont(descriptor: newDescriptor, size: 0.0)
			}
		}
	}

	private func modifyUserInfo(query: @escaping (inout PeerInfo) -> ()) {
		UserPeer.instance.modifyInfo { info in
			if var peerInfo = info {
				query(&peerInfo)
				info = peerInfo
			} else {
				AppDelegate.presentOnboarding()
			}
		}
	}

	private func registerForKeyboardNotifications() {
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWasShown), name: UIResponder.keyboardDidShowNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillBeHidden), name: UIResponder.keyboardWillHideNotification, object: nil)
	}
	
	/// Called when the UIKeyboardDidShowNotification is sent.
	@objc private func keyboardWasShown(aNotification: Notification) {
		guard let info = aNotification.userInfo, let (viewToShow, inputToShow) = activeField else { return }
		
		// TODO iOS 11 bug: we do only need to add the accessory height on our own, if the navigation bar is NOT collapsed
		// TEST with iOS < 11
		let accessoryHeight = inputToShow?.inputAccessoryView?.frame.height ?? 0.0
		let inputHeight = (info[UIResponder.keyboardFrameBeginUserInfoKey] as! CGRect).height
		let keyboardHeight = accessoryHeight + inputHeight

		let contentInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: keyboardHeight, right: 0.0)
		scrollView.contentInset = contentInsets
		scrollView.scrollIndicatorInsets = contentInsets
		
		// If active text field is hidden by keyboard, scroll it so it's visible
		var aRect = self.view.frame
		aRect.size.height -= keyboardHeight
		if (!aRect.contains(viewToShow.frame.origin) ) {
			scrollView.scrollRectToVisible(viewToShow.frame, animated: true)
		}
	}
	
	/// Called when the UIKeyboardWillHideNotification is sent
	@objc private func keyboardWillBeHidden(aNotification: Notification) {
		let contentInsets = UIEdgeInsets.zero
		scrollView.contentInset = contentInsets
		scrollView.scrollIndicatorInsets = contentInsets
	}

	/// Default handler for AccountController REST calls. Handles errors (if any) or calls <code>noErrorAction</code> on the main thread if no error occurred.
	private func accountActionCompletionHandler(_ _error: Error?, noErrorAction: @escaping () -> Void) {
		DispatchQueue.main.async {
			self.adjustAccountView()
			
			if let error = _error {
				InAppNotificationController.display(openapiError: error, localizedTitle: NSLocalizedString("Connection Error", comment: "Standard title message of alert for internet connection errors."))
			} else {
				noErrorAction()
			}
		}
	}
	
	private func adjustAccountView() {
		let accountExists = AccountController.shared.accountExists
		if accountExists {
			accountButton.setTitle(NSLocalizedString("Delete Identity", comment: "Caption of button"), for: .normal)
			accountButton.tintColor = .red
			mailTextField.text = AccountController.shared.accountEmail
			accountIDLabel.text = AccountController.shared.getPeerID()
		} else {
			accountButton.setTitle(NSLocalizedString("Create Identity", comment: "Caption of button"), for: .normal)
			accountButton.tintColor = AppTheme.tintColor
		}
		mailTextField.isHidden = !accountExists
		mailNoteLabel.isHidden = !accountExists
		accountIDLabel.isHidden = !accountExists
		accountButton.isEnabled = !(AccountController.shared.isCreatingAccount || AccountController.shared.isDeletingAccount)
		UserPeer.instance.read { peerInfo, _, _, _ in
			self.previewButton.isEnabled = accountExists && peerInfo != nil
		}
	}

	/// Do not allow changes to the user's peer while peering; show onboarding if peer does not exist.
	private func lockAndLoadView() {
		UserPeer.instance.read { peerInfo, birthday, picture, biograhy in
			let userPeerDefined = peerInfo != nil
			let peering = PeeringController.shared.peering
			let accountExists = AccountController.shared.accountExists
			let locked = !userPeerDefined || peering

			for control: UIControl in [self.nameTextField, self.portraitImageButton, self.genderControl, self.birthdayInput] {
				control.isEnabled = !locked
			}
			self.bioTextView.isEditable = !locked
			self.connectionNoteLabel.isHidden = !locked
			self.previewButton.isEnabled = userPeerDefined && accountExists

			self.loadUserPeerInfo(peerInfo: peerInfo, birthday: birthday, portrait: picture, bio: biograhy)

			if !userPeerDefined {
				AppDelegate.presentOnboarding()
			}
		}

	}
}
