//
//  MainDataViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class MeViewController: PortraitImagePickerController, UITextFieldDelegate {
	@IBOutlet private weak var nameTextField: UITextField!
	@IBOutlet private weak var statusButton: UIButton!
	@IBOutlet private weak var portraitImageButton: UIButton!
    @IBOutlet private weak var genderControl: UISegmentedControl!
    @IBOutlet private weak var birthdayInput: UITextField!
    @IBOutlet private weak var scrollView: UIScrollView!
	
	private class StatusSelViewControllerDataSource: NSObject, SingleSelViewControllerDataSource {
		private let container: MeViewController
		
		init(container: MeViewController) {
			self.container = container
		}
        
        fileprivate func initialPickerSelection(for pickerView: UIPickerView) -> (row: Int, inComponent: Int) {
            return (PeerInfo.RelationshipStatus.values.index(of: UserPeerInfo.instance.relationshipStatus)!, 0)
        }
        fileprivate func selectionEditable(in pickerView: UIPickerView) -> Bool {
            return true
        }
		
		func headingOfBasicDescriptionViewController(_ basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return NSLocalizedString("Relationship Status", comment: "Heading of the relation ship status picker view controller.")
		}
		
		func subHeadingOfBasicDescriptionViewController(_ basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return ""
		}
		
		func descriptionOfBasicDescriptionViewController(_ basicDescriptionViewController: BasicDescriptionViewController) -> String? {
			return NSLocalizedString("Tell others, what's up with your relationship.", comment: "Description of relation ship status picker view controller.")
		}
		
		@objc func numberOfComponents(in pickerView: UIPickerView) -> Int {
			return 1
		}
		
		@objc func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            return PeerInfo.RelationshipStatus.values.count
		}
		
		@objc func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
			return PeerInfo.RelationshipStatus.values[row].localizedRawValue
		}
		
		@objc func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
			UserPeerInfo.instance.relationshipStatus = PeerInfo.RelationshipStatus.values[row]
		}
	}
    
	@IBAction func changeGender(_ sender: UISegmentedControl) {
		UserPeerInfo.instance.gender = PeerInfo.Gender.values[sender.selectedSegmentIndex]
	}
    
    @IBAction func changePicture(_ sender: AnyObject) {
        showPicturePicker(true, destructiveActionName: NSLocalizedString("Delete Portrait", comment: "Removing the own portrait image."))
    }
    
    func agePickerChanged(_ sender: UIDatePicker) {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .none
        dateFormatter.dateStyle = .long
        birthdayInput.text = dateFormatter.string(from: sender.date)
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
            personDetailVC.displayedPeerID = UserPeerInfo.instance.peer.peerID
        } else if let singleSelVC = segue.destination as? SingleSelViewController {
            singleSelVC.dataSource = StatusSelViewControllerDataSource(container: self)
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
        var minComponents = (Calendar.current as NSCalendar).components([.day, .month, .year], from: today)
        minComponents.year = minComponents.year! - PeerInfo.MaxAge
        var maxComponents = (Calendar.current as NSCalendar).components([.day, .month, .year], from: today)
        maxComponents.year = maxComponents.year! - PeerInfo.MinAge
        
        datePicker.minimumDate = Calendar.current.date(from: minComponents)
        datePicker.maximumDate = Calendar.current.date(from: maxComponents)
        
        datePicker.date = UserPeerInfo.instance.dateOfBirth as Date? ?? datePicker.maximumDate ?? today
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
	}
	
	override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
		nameTextField.text = UserPeerInfo.instance.nickname
        statusButton.setTitle(UserPeerInfo.instance.relationshipStatus.rawValue, for: UIControlState())
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .none
        dateFormatter.dateStyle = .long
		genderControl.selectedSegmentIndex = PeerInfo.Gender.values.index(of: UserPeerInfo.instance.gender) ?? 0
        portraitImageButton.setImage(UserPeerInfo.instance.picture ?? UIImage(named: "PortraitUnavailable"), for: UIControlState())
        
        statusButton.setNeedsLayout()
	}
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        _ = CircleMaskView(maskedView: portraitImageButton.imageView!)
    }
	
	// MARK: UITextFieldDelegate
	
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        switch textField {
        case nameTextField:
            guard let newValue = textField.text else { return }
            UserPeerInfo.instance.nickname = newValue
        case birthdayInput:
            scrollView.contentInset = UIEdgeInsets.zero
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
	
	func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        guard textField == birthdayInput else { return true }
        
        scrollView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: birthdayInput.inputView?.frame.height ?? 0.0, right: 0.0)
		return true
    }
    
    // TODO do we need this anymore? or should we restrict it still but allow more characters?
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard textField == nameTextField else { return true }
        
        if (range.length + range.location > textField.text!.characters.count) {
            return false
        }
        
        let newLength = textField.text!.characters.count + string.characters.count - range.length
        return newLength <= 63
    }
    
    override func picked(image: UIImage?) {
        super.picked(image: image)
        portraitImageButton.setImage(image ?? UIImage(named: "PortraitUnavailable"), for: UIControlState())
    }
}
