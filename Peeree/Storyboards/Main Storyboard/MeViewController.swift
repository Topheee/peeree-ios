//
//  MainDataViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class MeViewController: UIViewController, UITextFieldDelegate, UserPeerInfoDelegate {
	@IBOutlet var scrollView: UIScrollView!
	@IBOutlet var contentView: UIView!
	
	@IBOutlet var forenameTextField: UITextField!
	@IBOutlet var lastnameTextField: UITextField!
	@IBOutlet var ageButton: UIButton!
	@IBOutlet var statusButton: UIButton!
	@IBOutlet var portraitImageView: UIImageView!
	@IBOutlet var genderControl: UISegmentedControl!
	
	private class StatusSelViewControllerDataSource: NSObject, SingleSelViewControllerDataSource {
		private let container: MeViewController
		
		init(container: MeViewController) {
			self.container = container
		}
		
		func headingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return NSLocalizedString("Relationship status", comment: "Heading of the relation ship status picker view controller")
		}
		
		func subHeadingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return ""
		}
		
		func descriptionOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return NSLocalizedString("Tell others, what's up with your relationship.", comment: "Description of relation ship status picker view controller")
		}
		
		@objc func numberOfComponentsInPickerView(pickerView: UIPickerView) -> Int {
			return 1
		}
		
		@objc func pickerView(pickerView: UIPickerView,
			numberOfRowsInComponent component: Int) -> Int {
				return SerializablePeerInfo.possibleStatuses.count
		}
		
		@objc func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
			return SerializablePeerInfo.possibleStatuses[row]
		}
		
		@objc func pickerView(pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
			UserPeerInfo.instance.statusID = row
//			container.statusButton.titleLabel?.text = SerializablePeerInfo.possibleStatuses[row]
		}
	}
	
	private class BirthSelViewControllerDataSource: NSObject, DateSelViewControllerDataSource {
		private let container: MeViewController
		
		init(container: MeViewController) {
			self.container = container
		}
		
		func headingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return NSLocalizedString("Date of Birth", comment: "Heading of the date of birth date picker view controller")
		}
		
		func subHeadingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return ""
		}
		
		func descriptionOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return NSLocalizedString("Tell others, what's up with your relationship.", comment: "Description of relation ship status picker view controller")
		}
		
		private func setupPicker(picker: UIDatePicker, inDateSel dateSelViewController: DateSelViewController) {
			//  TODO insert global min age
			picker.maximumDate = NSDate(timeInterval: -60*60*24*365*13, sinceDate: NSDate())
		}
	}
	
	@IBAction func changeGender(sender: UISegmentedControl) {
		UserPeerInfo.instance.hasVagina = sender.selectedSegmentIndex == 1
	}
	
	private var isIdentityChanging = false
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		if let singleSelVC = segue.destinationViewController as? SingleSelViewController {
			singleSelVC.dataSource = StatusSelViewControllerDataSource(container: self)
		} else if let charTraitVC = segue.destinationViewController as?
			CharacterTraitViewController {
			charTraitVC.characterTraits = UserPeerInfo.instance.characterTraits
		} else if let dateSelVC = segue.destinationViewController as? DateSelViewController {
			dateSelVC.dataSource = BirthSelViewControllerDataSource(container: self)
		}
		// TODO remove this
//		else if let multipleSelVC = segue.destinationViewController as? UITableViewController {
//			multipleSelVC.title = NSLocalizedString("Spoken Languages", comment: "Title of the spoken languages selection view controller")
//			multipleSelVC.tableView.dataSource = self
//			multipleSelVC.tableView.delegate = self
//		}
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		
		scrollView.layoutIfNeeded()
		scrollView.contentSize = contentView.bounds.size
	}
	
	override func viewDidLoad() {
		portraitImageView.maskView = CircleMaskView(forView: portraitImageView)
	}
	
	override func viewWillAppear(animated: Bool) {
		forenameTextField.text = UserPeerInfo.instance.givenName
		lastnameTextField.text = UserPeerInfo.instance.familyName
		statusButton.titleLabel?.text = SerializablePeerInfo.possibleStatuses[UserPeerInfo.instance.statusID]
		ageButton.titleLabel?.text = "\(UserPeerInfo.instance.age) years old"
		genderControl.selectedSegmentIndex = UserPeerInfo.instance.hasVagina ? 1 : 0
	}
	
	override func viewDidAppear(animated: Bool) {
		UserPeerInfo.instance.delegate = self
	}
	
	override func viewDidDisappear(animated: Bool) {
//		if UserPeerInfo.instance.delegate! == self as UserPeerInfoDelegate {
			UserPeerInfo.instance.delegate = nil
//		}
	}
	
	// MARK: -
	
	// MARK: UITextFieldDelegate
	
	func textFieldShouldReturn(textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
	
	func textFieldShouldEndEditing(textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		if let newValue = textField.text {
			switch textField {
			case forenameTextField:
				if newValue != UserPeerInfo.instance.givenName {
					isIdentityChanging = true
					UserPeerInfo.instance.givenName = newValue
				}
			case lastnameTextField:
				if newValue != UserPeerInfo.instance.familyName {
					isIdentityChanging = true
					UserPeerInfo.instance.familyName = newValue
				}
			default:
				break
			}
		}
		return true
	}
	
	func textFieldShouldBeginEditing(textField: UITextField) -> Bool {
		return !(isIdentityChanging || forenameTextField.isFirstResponder() || lastnameTextField.isFirstResponder())
	}
	
	func userCancelledIDChange() {
		isIdentityChanging = false
		forenameTextField.text = UserPeerInfo.instance.givenName
		lastnameTextField.text = UserPeerInfo.instance.familyName
	}
	
	func userConfirmedIDChange() {
		isIdentityChanging = false
	}
	
	func idChangeDialogPresented() {
		// nothing
	}
}