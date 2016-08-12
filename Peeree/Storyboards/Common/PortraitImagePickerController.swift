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
    func showPicturePicker(allowCancel: Bool = false, destructiveActionName: String, destructiveAction: ((UIAlertAction) -> Void)) {
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
        
        let alertController = UIAlertController()
        if UIImagePickerController.isSourceTypeAvailable(.Camera) {
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Camera", comment: "Camera of the device."), style: .Default, handler: cameraHandler))
        } else if UIImagePickerController.isSourceTypeAvailable(.PhotoLibrary) {
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Photo Library", comment: "Photo Library on the device."), style: .Default, handler: photoLibraryHandler))
        }
        alertController.addAction(UIAlertAction(title: destructiveActionName, style: .Destructive, handler: destructiveAction))
        if allowCancel {
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .Cancel, handler: nil))
        }
        alertController.present(nil)
    }
    
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
            
            pickedImage(imageToSave!)
        }
        
        // picker.parentViewController is nil, but I don't know why
        //        picker.parentViewController?.dismissViewControllerAnimated(true, completion: nil)
        self.dismissViewControllerAnimated(true, completion: nil)
    }
    
    func pickedImage(image: UIImage) {
        // may be overridden by subclasses
    }
}