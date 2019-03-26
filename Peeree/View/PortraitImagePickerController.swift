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

/// Base class for view controllers providing availablity to change the user's portrait image.
class PortraitImagePickerController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func showPicturePicker(_ allowCancel: Bool = false, destructiveActionName: String) {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.allowsEditing = true
        imagePicker.mediaTypes = [kUTTypeImage as String]
        
        let presentPicker = {
            DispatchQueue.main.async {
                self.present(imagePicker, animated: true, completion: nil)
                imagePicker.view.tintColor = AppDelegate.shared.theme.globalTintColor
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
        
        let alertController = UIAlertController()
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
            self.picked(image: nil)
        })
        if allowCancel {
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        }
        alertController.present()
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        // picker.parentViewController is nil, but I don't know why
        //        picker.parentViewController?.dismissViewControllerAnimated(true, completion: nil)
        self.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
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
            if picker.sourceType == .camera && PHPhotoLibrary.authorizationStatus() == .authorized {
                UIImageWriteToSavedPhotosAlbum(imageToSave!, nil, nil , nil)
            }
            
            picked(image: imageToSave)
        }
        
        // picker.parentViewController is nil, but I don't know why
        //        picker.parentViewController?.dismissViewControllerAnimated(true, completion: nil)
        self.dismiss(animated: true, completion: nil)
    }
    
    func picked(image: UIImage?) {
        UserPeerInfo.instance.picture = image
    }
}
