//
//  PortraitImagePickerController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.06.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit
import MobileCoreServices

/// Base class for view controllers providing availablity to change the user's portrait image.
class PortraitImagePickerController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func showPicturePicker(_ allowCancel: Bool = false, destructiveActionName: String, destructiveAction: @escaping ((UIAlertAction) -> Void)) {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.allowsEditing = true
        imagePicker.mediaTypes = [kUTTypeImage as String]
        
        let presentPicker = {
            self.present(imagePicker, animated: true, completion: nil)
            imagePicker.view.tintColor = theme.globalTintColor
        }
        let cameraHandler = {(alertAction: UIAlertAction) -> Void in
            imagePicker.sourceType = .camera
            presentPicker()
        }
        let photoLibraryHandler = {(alertAction: UIAlertAction) -> Void in
            imagePicker.sourceType = .photoLibrary
            presentPicker()
        }
        
        let alertController = UIAlertController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Camera", comment: "Camera of the device."), style: .default, handler: cameraHandler))
        } else if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Photo Library", comment: "Photo Library on the device."), style: .default, handler: photoLibraryHandler))
        }
        alertController.addAction(UIAlertAction(title: destructiveActionName, style: .destructive, handler: destructiveAction))
        if allowCancel {
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        }
        alertController.present(nil)
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
            if picker.sourceType == .camera {
                UIImageWriteToSavedPhotosAlbum(imageToSave!, nil, nil , nil)
            }
            
            pickedImage(imageToSave!)
        }
        
        // picker.parentViewController is nil, but I don't know why
        //        picker.parentViewController?.dismissViewControllerAnimated(true, completion: nil)
        self.dismiss(animated: true, completion: nil)
    }
    
    func pickedImage(_ image: UIImage) {
        // may be overridden by subclasses
    }
}
