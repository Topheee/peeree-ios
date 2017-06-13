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

//extension LocalPeerInfo {
//    var picture: UIImage? {
//        get { return peer.picture }
//        set { peer.picture = newValue }
//    }
//}

extension UserPeerInfo {
    /* override */ var picture: UIImage? {
        get { return peer.picture }
        set { peer.picture = newValue
//        didSet {
            dirtied()
            
            if picture != nil {
                // Don't block the UI when writing the image to documents
                DispatchQueue.global().async {
                    // Save the new image to the documents directory
                    do {
                        try UIImageJPEGRepresentation(self.picture!, 0.0)?.write(to: self.pictureResourceURL, options: .atomic)
                    } catch let error as NSError {
                        // TODO error handling
                        print(error.debugDescription)
                    }
                }
            } else {
                let fileManager = FileManager.default
                do {
                    if fileManager.fileExists(atPath: pictureResourceURL.path) {
                        try fileManager.removeItem(at: pictureResourceURL)
                    }
                } catch let error as NSError {
                    // TODO error handling
                    print(error.debugDescription)
                }
            }
        }
    }
}
