//
//  PeereeExtensionsiOS.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.02.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import UIKit

extension PeerInfo {
    var picture: UIImage? {
        get {
            return cgPicture != nil ? UIImage(cgImage: cgPicture!) : nil
        }
        set {
            cgPicture = newValue?.cgImage
        }
    }
}

extension UserPeerInfo {
    var picture: UIImage? {
        get { return peer.picture }
        set {
            let oldValue = picture
            guard newValue != oldValue else { return }
            
            peer.picture = newValue
            dirtied()
            
            if picture != nil {
                // Don't block the UI when writing the image to documents
                DispatchQueue.global().async {
                    // Save the new image to the documents directory
                    do {
                        try self.picture!.jpegData(compressionQuality: 0.0)?.write(to: self.pictureResourceURL, options: .atomic)
                    } catch let error as NSError {
                        NSLog(error.debugDescription)
                        DispatchQueue.main.async {
                            self.picture = oldValue
                        }
                    }
                }
            } else {
                let fileManager = FileManager.default
                do {
                    if fileManager.fileExists(atPath: pictureResourceURL.path) {
                        try fileManager.removeItem(at: pictureResourceURL)
                    }
                } catch let error as NSError {
                    NSLog(error.debugDescription)
                    DispatchQueue.main.async {
                        self.picture = oldValue
                    }
                }
            }
        }
    }
}
