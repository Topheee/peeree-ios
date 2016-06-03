//
//  MainDataViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import MobileCoreServices
import CoreFoundation

class MeViewController: UIViewController, UITextFieldDelegate, UIImagePickerControllerDelegate,
UINavigationControllerDelegate, UserPeerInfoDelegate {
	@IBOutlet private var scrollView: UIScrollView!
	@IBOutlet private var contentView: UIView!
	
	@IBOutlet private var forenameTextField: UITextField!
	@IBOutlet private var lastnameTextField: UITextField!
	@IBOutlet private var ageButton: UIButton!
	@IBOutlet private var statusButton: UIButton!
	@IBOutlet private var portraitImageButton: UIButton!
	@IBOutlet private var genderControl: UISegmentedControl!
	
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
            picker.date = UserPeerInfo.instance.dateOfBirth
		}
        
        private func pickerChanged(picker: UIDatePicker) {
            UserPeerInfo.instance.dateOfBirth = picker.date
        }
	}
	
	@IBAction func changeGender(sender: UISegmentedControl) {
		UserPeerInfo.instance.hasVagina = sender.selectedSegmentIndex == 1
	}
    @IBAction func changePicture(sender: AnyObject) {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.allowsEditing = true
        imagePicker.mediaTypes = [kUTTypeImage as String]
        
        let presentPicker = {
            self.presentViewController(imagePicker, animated: true, completion: nil)
        }
        let cameraHandler = {(alertAction: UIAlertAction) -> Void in
            imagePicker.sourceType = .Camera
            presentPicker()
        }
        let photoLibraryHandler = {(alertAction: UIAlertAction) -> Void in
            imagePicker.sourceType = .PhotoLibrary
            presentPicker()
        }
        
        if UIImagePickerController.isSourceTypeAvailable(.Camera) && UIImagePickerController.isSourceTypeAvailable(.PhotoLibrary) {
            let alertController = UIAlertController()
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Camera", comment: "Camera of the device"), style: .Default, handler: cameraHandler))
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Photo Library", comment: "Photo Library on the device"), style: .Default, handler: photoLibraryHandler))
            presentViewController(alertController, animated: true, completion: nil)
        } else if UIImagePickerController.isSourceTypeAvailable(.Camera) {
            cameraHandler(UIAlertAction(title: "", style: .Default, handler: nil))
        } else if UIImagePickerController.isSourceTypeAvailable(.PhotoLibrary) {
            photoLibraryHandler(UIAlertAction(title: "", style: .Default, handler: nil))
        }
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
		portraitImageButton.maskView = CircleMaskView(forView: portraitImageButton)
        forenameTextField.inputView = UIDatePicker()
	}
	
	override func viewWillAppear(animated: Bool) {
		forenameTextField.text = UserPeerInfo.instance.givenName
		lastnameTextField.text = UserPeerInfo.instance.familyName
        statusButton.setTitle(SerializablePeerInfo.possibleStatuses[UserPeerInfo.instance.statusID], forState: .Normal)
        let dateFormatter = NSDateFormatter()
        dateFormatter.timeStyle = .NoStyle
        dateFormatter.dateStyle = .LongStyle
        ageButton.setTitle(dateFormatter.stringFromDate(UserPeerInfo.instance.dateOfBirth), forState: .Normal)
		genderControl.selectedSegmentIndex = UserPeerInfo.instance.hasVagina ? 1 : 0
        portraitImageButton.imageView?.image = UserPeerInfo.instance.picture ?? UIImage(named: "Sample Profile Pick")
        
        for control in [ageButton, statusButton] {
            control.setNeedsLayout()
        }
	}
	
	override func viewDidAppear(animated: Bool) {
        UserPeerInfo.instance.delegate = self
	}
	
	override func viewDidDisappear(animated: Bool) {
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
    
    // MARK: - UIImagePickerController Delegate
    
    func imagePickerControllerDidCancel(picker: UIImagePickerController) {
        // picker.parentViewController is nil, but I don't know why
//        picker.parentViewController?.dismissViewControllerAnimated(true, completion: nil)
        self.dismissViewControllerAnimated(true, completion: nil)
    }
    
    func imagePickerController(picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : AnyObject]) {
        var originalImage, editedImage, imageToSave: UIImage?
            
        editedImage = info[UIImagePickerControllerEditedImage] as? UIImage
        originalImage = info[UIImagePickerControllerOriginalImage] as? UIImage
        
        if editedImage != nil {
            imageToSave = editedImage
        } else {
            imageToSave = originalImage
        }
        
        // Save the new image (original or edited) to the Camera Roll
        if imageToSave != nil {
            if picker.sourceType == .Camera {
                UIImageWriteToSavedPhotosAlbum(imageToSave!, nil, nil , nil)
            }
            
            UserPeerInfo.instance.picture = imageToSave
            portraitImageButton.imageView?.image = imageToSave
        }
        
        // picker.parentViewController is nil, but I don't know why
//        picker.parentViewController?.dismissViewControllerAnimated(true, completion: nil)
        self.dismissViewControllerAnimated(true, completion: nil)
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