//
//  PeereeExtensionsiOS.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.02.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import UIKit

extension PeerViewModel {
	var picture: UIImage? {
		get {
			return cgPicture.map { UIImage(cgImage: $0) }
		}
	}

	public func createRoundedPicture(cropRect: CGRect, backgroundColor: UIColor) -> UIImage? {
		return portraitOrPlaceholder.roundedCropped(cropRect: cropRect, backgroundColor: backgroundColor)
	}

	public var portraitOrPlaceholder: UIImage {
		return pictureClassification == .none ? picture ?? (peer.info.hasPicture ? #imageLiteral(resourceName: "PortraitPlaceholder") : #imageLiteral(resourceName: "PortraitUnavailable")) : #imageLiteral(resourceName: "ObjectionablePortraitPlaceholder")
	}
}

extension AppDelegate {
	func showOrMessage(peerID: PeerID) {
		if AccountController.shared.hasPinMatch(peerID) {
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
				guard someBeaconVC.peerID != peerID else { return }
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

	/// Must be called on the main thread!
	static func requestPin(of peerID: PeerID) {
		let model = PeerViewModelController.viewModel(of: peerID)
		if !model.verified {
			let alertController = UIAlertController(title: NSLocalizedString("Unverified Peer", comment: "Title of the alert which pops up when the user is about to pin an unverified peer"), message: NSLocalizedString("Be careful: the identity of this person is not verified, you may attempt to pin someone malicious!", comment: "Alert message if the user is about to pin someone who did not yet authenticate himself"), preferredStyle: UIDevice.current.iPadOrMac ? .alert : .actionSheet)
			let retryVerifyAction = UIAlertAction(title: NSLocalizedString("Retry verify", comment: "The user wants to retry verifying peer"), style: .`default`) { action in
				PeeringController.shared.interact(with: peerID) { interaction in
					interaction.verify()
				}
			}
			alertController.addAction(retryVerifyAction)
			let actionTitle = String(format: NSLocalizedString("Pin %@", comment: "The user wants to pin the person, whose name is given in the format argument"), model.peer.info.nickname)
			alertController.addAction(UIAlertAction(title: actionTitle, style: .destructive) { action in
				AccountController.shared.pin(model.peer.id)
			})
			alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
			alertController.preferredAction = retryVerifyAction
			alertController.present()
		} else if !AccountController.shared.accountExists {
			InAppNotificationController.display(title: NSLocalizedString("Peeree Identity Required", comment: "Title of alert when the user wants to go online but lacks an account and it's creation failed."), message: NSLocalizedString("Tap to create your Peeree identity.", comment: "The user lacks a Peeree account")) /*{
				(AppDelegate.shared.window?.rootViewController as? UITabBarController)?.selectedIndex = AppDelegate.MeTabBarIndex
			}*/
		} else {
			AccountController.shared.pin(model.peer.id)
		}
	}
}
