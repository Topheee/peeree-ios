//
//  PortraitImagePickerController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.06.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit
import MobileCoreServices
import Photos

protocol PortraitImagePickerControllerDelegate: AnyObject {
	func viewControllerToPresentImagePicker() -> UIViewController
	func picked(image: UIImage?)
}

/// Provides the ability to change the user's portrait image.
final class PortraitImagePickerController: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
	weak var delegate: PortraitImagePickerControllerDelegate?

	/// Displays the system's UI for capturing an image with the camera.
	func showPicturePicker(allowCancel: Bool, destructiveActionName: String) {
		let imagePicker = UIImagePickerController()
		imagePicker.delegate = self
		imagePicker.allowsEditing = true
		imagePicker.mediaTypes = [kUTTypeImage as String]
		
		let presentPicker = {
			DispatchQueue.main.async {
				self.delegate?.viewControllerToPresentImagePicker().present(imagePicker, animated: true, completion: nil)
				imagePicker.view.tintColor = AppTheme.tintColor
			}
		}
		let cameraHandler = {(alertAction: UIAlertAction) -> Void in
			imagePicker.sourceType = .camera
			imagePicker.showsCameraControls = true
			presentPicker()
		}
		let photoLibraryHandler = {(alertAction: UIAlertAction) -> Void in
			imagePicker.sourceType = .photoLibrary
			presentPicker()
		}
		
		let alertController = UIAlertController(title: nil, message: nil, preferredStyle: UIDevice.current.iPadOrMac ? .alert : .actionSheet)
		let cameraAction = UIAlertAction(title: NSLocalizedString("Camera", comment: "Camera of the device."), style: .`default`, handler: cameraHandler)
		cameraAction.isEnabled = UIImagePickerController.isSourceTypeAvailable(.camera)
		alertController.addAction(cameraAction)
		let photoLibraryAction = UIAlertAction(title: NSLocalizedString("Photo Library", comment: "Photo Library on the device."), style: .`default`, handler: photoLibraryHandler)
		photoLibraryAction.isEnabled = UIImagePickerController.isSourceTypeAvailable(.photoLibrary)
		alertController.addAction(photoLibraryAction)
		if cameraAction.isEnabled {
			alertController.preferredAction = cameraAction
		} else if photoLibraryAction.isEnabled {
			alertController.preferredAction = photoLibraryAction
		}
		alertController.addAction(UIAlertAction(title: destructiveActionName, style: .destructive) { (action) in
			self.save(image: nil)
		})
		if allowCancel {
			_ = alertController.addCancelAction()
		}
		alertController.present()
	}
	
	public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
		if let vc = picker.presentingViewController {
			vc.dismiss(animated: true, completion: nil)
		} else {
			self.delegate?.viewControllerToPresentImagePicker().dismiss(animated: true, completion: nil)
		}
	}
	
	public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
		var originalImage, editedImage, imageToSave: UIImage?
		
		editedImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage
		originalImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage
		
		if editedImage != nil {
			imageToSave = editedImage
		} else {
			imageToSave = originalImage
		}
		
		// Save the new image (original or edited) to the Camera Roll
		if imageToSave != nil {
			if picker.sourceType == .camera && PHPhotoLibrary.authorizationStatus() == .authorized {
				UIImageWriteToSavedPhotosAlbum(imageToSave!, nil, nil , nil)
			}
			
			save(image: imageToSave)
		}
		
		if let vc = picker.presentingViewController {
			vc.dismiss(animated: true, completion: nil)
		} else {
			self.delegate?.viewControllerToPresentImagePicker().dismiss(animated: true, completion: nil)
		}
	}
	
	private func save(image: UIImage?) {
		UserPeer.instance.modify(portrait: image?.cgImage)
		delegate?.picked(image: image)
	}
}
