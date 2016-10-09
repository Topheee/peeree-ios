//
//  MainDataViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
//import MultipeerConnectivity

final class MeViewController: PortraitImagePickerController, UITextFieldDelegate, UserPeerInfoDelegate {
	@IBOutlet private var nameTextField: UITextField!
	@IBOutlet private var statusButton: UIButton!
	@IBOutlet private var portraitImageButton: UIButton!
    @IBOutlet private var genderControl: UISegmentedControl!
    @IBOutlet private weak var birthdayInput: UITextField!
    @IBOutlet private weak var scrollView: UIScrollView!
	
	private class StatusSelViewControllerDataSource: NSObject, SingleSelViewControllerDataSource {
		private let container: MeViewController
		
		init(container: MeViewController) {
			self.container = container
		}
        
        private func initialPickerSelection(pickerView: UIPickerView) -> (row: Int, inComponent: Int) {
            return (PeerInfo.RelationshipStatus.values.indexOf(UserPeerInfo.instance.relationshipStatus)!, 0)
        }
        private func selectionEditable(pickerView: UIPickerView) -> Bool {
            return true
        }
		
		func headingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return NSLocalizedString("Relationship Status", comment: "Heading of the relation ship status picker view controller.")
		}
		
		func subHeadingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return ""
		}
		
		func descriptionOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return NSLocalizedString("Tell others, what's up with your relationship.", comment: "Description of relation ship status picker view controller.")
		}
		
		@objc func numberOfComponentsInPickerView(pickerView: UIPickerView) -> Int {
			return 1
		}
		
		@objc func pickerView(pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            return PeerInfo.RelationshipStatus.values.count
		}
		
		@objc func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
			return PeerInfo.RelationshipStatus.values[row].localizedRawValue
		}
		
		@objc func pickerView(pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
			UserPeerInfo.instance.relationshipStatus = PeerInfo.RelationshipStatus.values[row]
		}
	}
    
	@IBAction func changeGender(sender: UISegmentedControl) {
		UserPeerInfo.instance.gender = PeerInfo.Gender.values[sender.selectedSegmentIndex]
	}
    
    @IBAction func changePicture(sender: AnyObject) {
        showPicturePicker(true, destructiveActionName: NSLocalizedString("Delete Portrait", comment: "Removing the own portrait image.")) { (action) in
            UserPeerInfo.instance.picture = nil
            self.portraitImageButton.setImage(UIImage(named: "PortraitUnavailable")!, forState: .Normal)
        }
    }
    
    func agePickerChanged(sender: UIDatePicker) {
        let dateFormatter = NSDateFormatter()
        dateFormatter.timeStyle = .NoStyle
        dateFormatter.dateStyle = .LongStyle
        birthdayInput.text = dateFormatter.stringFromDate(sender.date)
    }
    
    func ageConfirmed(sender: UIBarButtonItem) {
        birthdayInput.resignFirstResponder()
    }
    
    func ageOmitted(sender: UIBarButtonItem) {
        birthdayInput.text = nil
        birthdayInput.resignFirstResponder()
    }
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        super.prepareForSegue(segue, sender: sender)
        if let personDetailVC = segue.destinationViewController as? PersonDetailViewController {
            personDetailVC.displayedPeerID = UserPeerInfo.instance.peer.peerID
        } else if let singleSelVC = segue.destinationViewController as? SingleSelViewController {
            singleSelVC.dataSource = StatusSelViewControllerDataSource(container: self)
        } else if let charTraitVC = segue.destinationViewController as? CharacterTraitViewController {
			charTraitVC.characterTraits = UserPeerInfo.instance.peer.characterTraits
		}
	}
	
	override func viewDidLoad() {
        super.viewDidLoad()

        let today = NSDate()
        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .Date
        let minComponents = NSCalendar.currentCalendar().components([.Day, .Month, .Year], fromDate: today)
        minComponents.year = minComponents.year - PeerInfo.MaxAge
        let maxComponents = NSCalendar.currentCalendar().components([.Day, .Month, .Year], fromDate: today)
        maxComponents.year = maxComponents.year - PeerInfo.MinAge
        
        datePicker.minimumDate = NSCalendar.currentCalendar().dateFromComponents(minComponents)
        datePicker.maximumDate = NSCalendar.currentCalendar().dateFromComponents(maxComponents)
        
        datePicker.date = UserPeerInfo.instance.dateOfBirth ?? datePicker.maximumDate ?? today
        datePicker.addTarget(self, action: #selector(agePickerChanged), forControlEvents: .ValueChanged)
        
        let saveToolBar = UIToolbar()
        let omitButton = UIBarButtonItem(title: NSLocalizedString("Omit", comment: ""), style: .Plain, target: self, action: #selector(ageOmitted))
        let spaceButton = UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: NSLocalizedString("Done", comment: ""), style: .Done, target: self, action: #selector(ageConfirmed))

        spaceButton.title = birthdayInput.placeholder
        omitButton.tintColor = UIColor.redColor()
        saveToolBar.translucent = true
        saveToolBar.sizeToFit()
        saveToolBar.setItems([omitButton,spaceButton,doneButton], animated: false)
        saveToolBar.userInteractionEnabled = true
        
        birthdayInput.inputView = datePicker
        birthdayInput.inputAccessoryView = saveToolBar
        birthdayInput.delegate = self
	}
	
	override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
		nameTextField.text = UserPeerInfo.instance.peerName
        statusButton.setTitle(UserPeerInfo.instance.relationshipStatus.rawValue, forState: .Normal)
        let dateFormatter = NSDateFormatter()
        dateFormatter.timeStyle = .NoStyle
        dateFormatter.dateStyle = .LongStyle
		genderControl.selectedSegmentIndex = PeerInfo.Gender.values.indexOf(UserPeerInfo.instance.gender) ?? 0
        portraitImageButton.setImage(UserPeerInfo.instance.picture ?? UIImage(named: "PortraitUnavailable"), forState: .Normal)
        
        statusButton.setNeedsLayout()
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
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        portraitImageButton.imageView?.maskView = CircleMaskView(frame: portraitImageButton.bounds)
    }
	
	// MARK: UITextFieldDelegate
	
	func textFieldShouldReturn(textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
    
    func textFieldDidEndEditing(textField: UITextField) {
        switch textField {
        case nameTextField:
            guard let newValue = textField.text else { return }
            UserPeerInfo.instance.peerName = newValue
        case birthdayInput:
            scrollView.contentInset = UIEdgeInsetsZero
            guard textField.text != nil && textField.text != "" else {
                UserPeerInfo.instance.dateOfBirth = nil
                return
            }
            guard let datePicker = textField.inputView as? UIDatePicker else { return }
            UserPeerInfo.instance.dateOfBirth = datePicker.date
        default:
            break
        }
        
    }
	
	func textFieldShouldBeginEditing(textField: UITextField) -> Bool {
        guard textField == birthdayInput else { return true }
        
        scrollView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: birthdayInput.inputView?.frame.height ?? 0.0, right: 0.0)
		return true
    }
    
    func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
        guard textField == nameTextField else { return true }
        
        if (range.length + range.location > textField.text!.characters.count) {
            return false
        }
        
        let newLength = textField.text!.characters.count + string.characters.count - range.length
        return newLength <= 63 //MCPeerID.MaxDisplayNameUTF8Length
    }
    
    override func pickedImage(image: UIImage) {
        UserPeerInfo.instance.picture = image
        portraitImageButton.setImage(image, forState: .Normal)
    }
    
    // MARK: UserPeerInfoDelegate
	
	func userCancelledIDChange() {
		nameTextField.text = UserPeerInfo.instance.peerName
	}
	
	func userConfirmedIDChange() {
		// nothing
	}
	
	func idChangeDialogPresented() {
		// nothing
	}
}