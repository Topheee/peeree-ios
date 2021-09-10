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

	public func createRoundedPicture(cropRect: CGRect, backgroundColor: UIColor) -> UIImage? {
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

extension AppDelegate {
	func showOrMessage(peerID: PeerID) {
		if PeeringController.shared.manager(for: peerID).peerInfo?.pinMatched ?? false {
			displayMessageViewController(for: peerID)
		} else {
			show(peerID: peerID)
		}
	}

	func show(peerID: PeerID) {
		guard let tabBarVC = window?.rootViewController as? UITabBarController,
			  let browseNavVC = tabBarVC.viewControllers?[AppDelegate.BrowseTabBarIndex] as? UINavigationController else { return }

		browseNavVC.presentedViewController?.dismiss(animated: false, completion: nil)

		var browseVC: BrowseViewController? = nil
		for vc in browseNavVC.viewControllers {
			if vc is BrowseViewController {
				browseVC = vc as? BrowseViewController
			} else if let personVC = vc as? PersonDetailViewController {
				guard personVC.peerID != peerID else { return }
			}
		}
		browseVC?.performSegue(withIdentifier: BrowseViewController.ViewPeerSegueID, sender: peerID)
	}

	func displayMessageViewController(for peerID: PeerID) {
		guard let tabBarVC = window?.rootViewController as? UITabBarController,
			  let pinMatchNavVC = tabBarVC.viewControllers?[AppDelegate.PinMatchesTabBarIndex] as? UINavigationController else { return }

		pinMatchNavVC.presentedViewController?.dismiss(animated: false, completion: nil)

		var pinMatchVC: PinMatchTableViewController? = nil
		for vc in pinMatchNavVC.viewControllers {
			if vc is PinMatchTableViewController {
				pinMatchVC = vc as? PinMatchTableViewController
			} else if let messageVC = vc as? MessagingViewController {
				guard messageVC.peerID != peerID else { return }
			}
		}
		guard let pinMatchesTableVC = pinMatchVC else { return }
		tabBarVC.selectedIndex = AppDelegate.PinMatchesTabBarIndex
		pinMatchesTableVC.performSegue(withIdentifier: PinMatchTableViewController.MessagePeerSegueID, sender: peerID)
	}

	func find(peerID: PeerID) {
		guard let tabBarVC = window?.rootViewController as? UITabBarController,
			  let browseNavVC = tabBarVC.viewControllers?[AppDelegate.BrowseTabBarIndex] as? UINavigationController else { return }

		browseNavVC.presentedViewController?.dismiss(animated: false, completion: nil)

		// find possibly existing VCs displaying regarded PeerID
		var _browseVC: BrowseViewController? = nil
		var _personVC: PersonDetailViewController? = nil
		for vc in browseNavVC.viewControllers {
			if vc is BrowseViewController {
				_browseVC = vc as? BrowseViewController
			} else if let somePersonVC = vc as? PersonDetailViewController {
				if somePersonVC.peerID == peerID {
					_personVC = somePersonVC
				}
			} else if let someBeaconVC = vc as? BeaconViewController {
				guard someBeaconVC.peerManager.peerInfo?.peerID != peerID else { return }
			}
		}

		if let personVC = _personVC {
			personVC.performSegue(withIdentifier: PersonDetailViewController.beaconSegueID, sender: nil)
		} else if let browseVC = _browseVC {
			guard let personVC = browseVC.storyboard?.instantiateViewController(withIdentifier: PersonDetailViewController.storyboardID) as? PersonDetailViewController,
				let findVC = browseVC.storyboard?.instantiateViewController(withIdentifier: BeaconViewController.storyboardID) as? BeaconViewController else { return }
			personVC.peerID = peerID
			browseNavVC.pushViewController(personVC, animated: false)
			findVC.peerID = peerID
			browseNavVC.pushViewController(findVC, animated: false)
		}
	}

	static func requestPin(of peer: PeerInfo) {
		let manager = PeeringController.shared.manager(for: peer.peerID)
		if !manager.verified {
			let alertController = UIAlertController(title: NSLocalizedString("Unverified Peer", comment: "Title of the alert which pops up when the user is about to pin an unverified peer"), message: NSLocalizedString("Be careful: the identity of this person is not verified, you may attempt to pin someone malicious!", comment: "Alert message if the user is about to pin someone who did not yet authenticate himself"), preferredStyle: UIDevice.current.iPadOrMac ? .alert : .actionSheet)
			let retryVerifyAction = UIAlertAction(title: NSLocalizedString("Retry verify", comment: "The user wants to retry verifying peer"), style: .`default`) { action in
				manager.verify()
			}
			alertController.addAction(retryVerifyAction)
			let actionTitle = String(format: NSLocalizedString("Pin %@", comment: "The user wants to pin the person, whose name is given in the format argument"), peer.nickname)
			alertController.addAction(UIAlertAction(title: actionTitle, style: .destructive) { action in
				AccountController.shared.pin(peer)
			})
			alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
			alertController.preferredAction = retryVerifyAction
			alertController.present()
		} else {
			AccountController.shared.pin(peer)
		}
	}
}
