//
//  PeereeExtensionsiOS.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.02.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import UIKit

extension PeerManager {
	var picture: UIImage? {
		get {
			return cgPicture.map { UIImage(cgImage: $0) }
		}
		set {
			cgPicture = newValue?.cgImage
		}
	}

	public func createRoundedPicture(cropRect: CGRect, backgroundColor: UIColor?) -> UIImage? {
		let image = pictureClassification == .none ? picture ?? (peerInfo?.hasPicture ?? false ? #imageLiteral(resourceName: "PortraitPlaceholder") : #imageLiteral(resourceName: "PortraitUnavailable")) : #imageLiteral(resourceName: "ObjectionablePortraitPlaceholder")
		return image.roundedCropped(cropRect: cropRect, backgroundColor: backgroundColor)
	}
}

extension UserPeerManager {
	/// Not thread-safe! You need to ensure it doesn't get called simultaneously
	func set(picture: UIImage?, completion: @escaping (NSError?) -> Void) {
		// Don't block the UI when writing the image to documents
		// this is not 100% safe, as two concurrent calls to this method can dispatch to different queues (global() doesn't always return the same queue)
		DispatchQueue.global(qos: .background).async {
			let oldValue = self.picture
			guard picture != oldValue else { return }
			
			do {
				if picture != nil {
					// Save the new image to the documents directory
					try picture!.jpegData(compressionQuality: 0.0)?.write(to: UserPeerManager.pictureResourceURL, options: .atomic)
				} else {
					let fileManager = FileManager.default
					if fileManager.fileExists(atPath: UserPeerManager.pictureResourceURL.path) {
						try fileManager.removeItem(at: UserPeerManager.pictureResourceURL)
					}
				}
			} catch let error as NSError {
				completion(error)
			}
			
			self.picture = picture
			if !(oldValue == nil && picture == nil || oldValue != nil && picture != nil) { self.dirtied() }
			completion(nil)
		}
	}
}
