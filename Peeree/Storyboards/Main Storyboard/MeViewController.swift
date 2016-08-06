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
	@IBOutlet private var birthdayButton: UIButton!
	@IBOutlet private var statusButton: UIButton!
	@IBOutlet private var portraitImageButton: UIButton!
    @IBOutlet private var genderControl: UISegmentedControl!
	
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
			return PeerInfo.RelationshipStatus.values[row].localizedRawValue()
		}
		
		@objc func pickerView(pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
			UserPeerInfo.instance.relationshipStatus = PeerInfo.RelationshipStatus.values[row]
		}
	}
	
	private class BirthSelViewControllerDataSource: NSObject, DateSelViewControllerDataSource {
		private let container: MeViewController
		
		init(container: MeViewController) {
			self.container = container
		}
		
		func headingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return NSLocalizedString("Age Selection", comment: "Heading of the date of birth date picker view controller.")
		}
		
		func subHeadingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return NSLocalizedString("Your (sugarcoated) date of birth", comment: "Sub heading of the date of birth selection view.")
		}
		
		func descriptionOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return NSLocalizedString("Others won't see your date of birth as is, but only your age in years, and you may of course lie on this. However, remember that others do filter this value.", comment: "Description of date of birth picker view.")
		}
		
		private func setupPicker(picker: UIDatePicker, inDateSel dateSelViewController: DateSelViewController) {
            let minComponents = NSDateComponents()
            minComponents.year = -NSCalendar.currentCalendar().component(.Year, fromDate: NSDate()) - PeerInfo.MaxAge
            let maxComponents = NSDateComponents()
            maxComponents.year = -NSCalendar.currentCalendar().component(.Year, fromDate: NSDate()) - PeerInfo.MinAge
            
            picker.minimumDate = NSCalendar.currentCalendar().dateByAddingComponents(minComponents, toDate: NSDate(), options: [])
			picker.maximumDate = NSCalendar.currentCalendar().dateByAddingComponents(maxComponents, toDate: NSDate(), options: [])
            
            picker.date = UserPeerInfo.instance.dateOfBirth ?? picker.maximumDate ?? NSDate()
		}
        
        private func pickerChanged(picker: UIDatePicker) {
            UserPeerInfo.instance.dateOfBirth = picker.date
        }
	}
	
	@IBAction func changeGender(sender: UISegmentedControl) {
		UserPeerInfo.instance.gender = PeerInfo.Gender.values[sender.selectedSegmentIndex]
	}
    @IBAction func changePicture(sender: AnyObject) {
        showPicturePicker(true, destructiveActionName: NSLocalizedString("Delete Portrait", comment: "Removing the own portrait image.")) { (action) in
            UserPeerInfo.instance.picture = nil
            self.portraitImageButton.setImage(UIImage(named: "PersonPlaceholder")!, forState: .Normal)
        }
    }
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        super.prepareForSegue(segue, sender: sender)
        if let personDetailVC = segue.destinationViewController as? PersonDetailViewController {
            personDetailVC.displayedPeerID = UserPeerInfo.instance.peer.peerID
        } else if let singleSelVC = segue.destinationViewController as? SingleSelViewController {
            singleSelVC.dataSource = StatusSelViewControllerDataSource(container: self)
        } else if let charTraitVC = segue.destinationViewController as?
			CharacterTraitViewController {
			charTraitVC.characterTraits = UserPeerInfo.instance.peer.characterTraits
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
        statusButton.setTitle(UserPeerInfo.instance.relationshipStatus.rawValue, forState: .Normal)
        let dateFormatter = NSDateFormatter()
        dateFormatter.timeStyle = .NoStyle
        dateFormatter.dateStyle = .LongStyle
        birthdayButton.setTitle(dateFormatter.stringFromDate(UserPeerInfo.instance.dateOfBirth), forState: .Normal)
		genderControl.selectedSegmentIndex = PeerInfo.Gender.values.indexOf(UserPeerInfo.instance.gender) ?? 0
        portraitImageButton.setImage(UserPeerInfo.instance.picture ?? UIImage(named: "PersonPlaceholder")!, forState: .Normal)
        
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
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        portraitImageButton.imageView?.maskView = CircleMaskView(forView: portraitImageButton)
    }
	
	// MARK: - UITextField Delegate
	
	func textFieldShouldReturn(textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
    
    func textFieldDidEndEditing(textField: UITextField) {
        guard let newValue = textField.text else { return }
        UserPeerInfo.instance.peerName = newValue
    }
	
	func textFieldShouldBeginEditing(textField: UITextField) -> Bool {
		return true
    }
    
    func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
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