//
//  SetupViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 24.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class SetupViewController: UIViewController, UITextFieldDelegate, PortraitImagePickerControllerDelegate {
	@IBOutlet private weak var picButton: UIButton!
	@IBOutlet private weak var nameTextField: UITextField!
	@IBOutlet private weak var genderPicker: UISegmentedControl!
	@IBOutlet private weak var birthdayInput: UITextField!

	private let portraitImagePicker = PortraitImagePickerController()

	@IBAction func takePic(_ sender: UIButton) {
		nameTextField.resignFirstResponder()
		portraitImagePicker.delegate = self
		portraitImagePicker.showPicturePicker(allowCancel: false, destructiveActionName: NSLocalizedString("Omit Portrait", comment: "Don't set a profile picture during onboarding."))
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		if picButton.mask == nil, let imageView = picButton.imageView {
			_ = CircleMaskView(maskedView: imageView)
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		guard let chosenName = nameTextField.text, chosenName != "" else { return }

		let gender = PeerInfo.Gender.allCases[self.genderPicker.selectedSegmentIndex]
		UserPeer.instance.modifyInfo { info in
			info = PeerInfo(nickname: chosenName, gender: gender, age: nil, hasPicture: false)
		}
	}
	
	override var prefersStatusBarHidden : Bool {
		return true
	}

	// MARK: PortraitImagePickerControllerDelegate

	func picked(image: UIImage?) {
		picButton.setImage(image ?? #imageLiteral(resourceName: "PortraitUnavailable"), for: [])
		if #available(iOS 11.0, *) {
			picButton.accessibilityIgnoresInvertColors = image != nil
		}
	}

	func viewControllerToPresentImagePicker() -> UIViewController {
		return self
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

		datePicker.date = datePicker.maximumDate ?? today
		datePicker.addTarget(self, action: #selector(self.agePickerChanged), for: .valueChanged)

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
	
	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		return textField.allowChangeCharacters(in: range, replacementString: string, maxUtf8Length: PeerInfo.MaxNicknameSize)
	}

	@objc private func agePickerChanged(_ sender: UIDatePicker) {
		UserPeer.instance.modify(birthday: sender.date)
		fillBirthdayInput(with: sender.date)
	}

	@objc private func ageConfirmed(_ sender: UIBarButtonItem) {
		birthdayInput.resignFirstResponder()
	}

	@objc private func ageOmitted(_ sender: UIBarButtonItem) {
		UserPeer.instance.modify(birthday: nil)
		birthdayInput.text = nil
		birthdayInput.resignFirstResponder()
	}

	private func fillBirthdayInput(with date: Date) {
		let dateFormatter = DateFormatter()
		dateFormatter.timeStyle = .none
		dateFormatter.dateStyle = .long
		birthdayInput.text = dateFormatter.string(from: date)
	}
}
