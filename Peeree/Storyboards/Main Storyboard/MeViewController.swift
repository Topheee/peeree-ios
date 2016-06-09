//
//  MainDataViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class MeViewController: PortraitImagePickerController, UITextFieldDelegate, UserPeerInfoDelegate {
	@IBOutlet private var nameTextField: UITextField!
	@IBOutlet private var birthdayButton: UIButton!
	@IBOutlet private var statusButton: UIButton!
	@IBOutlet private var portraitImageButton: UIButton!
    @IBOutlet private var genderControl: UISegmentedControl!
    
    private var isIdentityChanging = false
	
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
		
		@objc func pickerView(pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            return SerializablePeerInfo.possibleStatuses.count
		}
		
		@objc func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
			return SerializablePeerInfo.possibleStatuses[row]
		}
		
		@objc func pickerView(pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
			UserPeerInfo.instance.statusID = row
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
			//  TODO create global min age constant from this value
			picker.maximumDate = NSDate(timeInterval: -60*60*24*365*13, sinceDate: NSDate())
            picker.date = UserPeerInfo.instance.dateOfBirth ?? picker.maximumDate!
		}
        
        private func pickerChanged(picker: UIDatePicker) {
            UserPeerInfo.instance.dateOfBirth = picker.date
        }
	}
	
	@IBAction func changeGender(sender: UISegmentedControl) {
		UserPeerInfo.instance.hasVagina = sender.selectedSegmentIndex == 1
	}
    @IBAction func changePicture(sender: AnyObject) {
        showPicturePicker(NSLocalizedString("Delete portrait", comment: "Removing the own portrait image")) { (action) in
            UserPeerInfo.instance.picture = nil
        }
    }
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        super.prepareForSegue(segue, sender: sender)
        if let personDetailVC = segue.destinationViewController as? PersonDetailViewController {
            personDetailVC.displayedPeer = UserPeerInfo.instance.peerID
        } else if let singleSelVC = segue.destinationViewController as? SingleSelViewController {
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
	
	override func viewDidLoad() {
        super.viewDidLoad()
        nameTextField.keyboardType = UIKeyboardType.NamePhonePad
	}
	
	override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
		nameTextField.text = UserPeerInfo.instance.peerName
        statusButton.setTitle(SerializablePeerInfo.possibleStatuses[UserPeerInfo.instance.statusID], forState: .Normal)
        let dateFormatter = NSDateFormatter()
        dateFormatter.timeStyle = .NoStyle
        dateFormatter.dateStyle = .LongStyle
        if let birthday = UserPeerInfo.instance.dateOfBirth {
            birthdayButton.setTitle(dateFormatter.stringFromDate(birthday), forState: .Normal)
        }
		genderControl.selectedSegmentIndex = UserPeerInfo.instance.hasVagina ? 1 : 0
        portraitImageButton.imageView?.image = UserPeerInfo.instance.picture ?? UIImage(named: "Sample Profile Pick")
        portraitImageButton.imageView?.maskView = CircleMaskView(forView: portraitImageButton)
        
        for control in [birthdayButton, statusButton] {
            control.setNeedsLayout()
        }
	}
	
	override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        UserPeerInfo.instance.delegate = self
	}
	
	override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
//		if UserPeerInfo.instance.delegate! == self as UserPeerInfoDelegate {
			UserPeerInfo.instance.delegate = nil
//		}
	}
	
	// MARK: - UITextField Delegate
	
	func textFieldShouldReturn(textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
	
	func textFieldShouldEndEditing(textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		guard let newValue = textField.text else {
            return true
        }
        
        switch textField {
        case nameTextField:
            if newValue != UserPeerInfo.instance.peerName {
                isIdentityChanging = true
                UserPeerInfo.instance.peerName = newValue
            }
        default:
            break
        }
		return true
	}
	
	func textFieldShouldBeginEditing(textField: UITextField) -> Bool {
		return !(isIdentityChanging || nameTextField.isFirstResponder())
    }
    
    override func pickedImage(image: UIImage) {
        UserPeerInfo.instance.picture = image
        portraitImageButton.setImage(image, forState: .Normal)
    }
    
	
	func userCancelledIDChange() {
		isIdentityChanging = false
		nameTextField.text = UserPeerInfo.instance.peerName
	}
	
	func userConfirmedIDChange() {
		isIdentityChanging = false
	}
	
	func idChangeDialogPresented() {
		// nothing
	}
}