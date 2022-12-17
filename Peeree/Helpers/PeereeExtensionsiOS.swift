//
//  PeereeExtensionsiOS.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.02.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import UIKit
import SafariServices

extension PeerViewModel {
	var picture: UIImage? {
		get {
			return cgPicture.map { UIImage(cgImage: $0) }
		}
	}

	public func createRoundedPicture(cropRect: CGRect, backgroundColor: UIColor) -> UIImage? {
		return portraitOrPlaceholder.roundedCropped(cropRect: cropRect, backgroundColor: backgroundColor)
	}

	/// Obtains the peer's picture or a placeholder, depending on the objectionable content classification.
	public var portraitOrPlaceholder: UIImage {
		return pictureClassification == .objectionable ? #imageLiteral(resourceName: "ObjectionablePortraitPlaceholder") : picture ?? (info.hasPicture ? #imageLiteral(resourceName: "PortraitPlaceholder") : #imageLiteral(resourceName: "PortraitUnavailable"))
	}
}

extension AppDelegate {

	/// Calls `AccountController.createAccount` and displays its error.
	static func createIdentity(displayError: Bool = true) {
		AccountController.createAccount { result in
			switch result {
			case .success(_):
				break
			case .failure(let error):
				guard displayError else { return }
				InAppNotificationController.display(openapiError: error, localizedTitle: NSLocalizedString("Account Creation Failed", comment: "Title of alert"), furtherDescription: NSLocalizedString("Please go to the bottom of your profile to try again.", comment: "Further description of account creation failure error"))
			}
		}
	}

	/// Display appropriate view controller for `peerID`.
	func showOrMessage(peerID: PeerID) {
		if PeereeIdentityViewModelController.viewModels[peerID]?.pinState == .pinMatch {
			displayMessageViewController(for: peerID)
		} else {
			show(peerID: peerID)
		}
	}

	func show(peerID: PeerID) {
		guard let tabBarVC = window?.rootViewController as? UITabBarController,
			  let browseNavVC = tabBarVC.viewControllers?[AppDelegate.BrowseTabBarIndex] as? UINavigationController else { return }

		browseNavVC.presentedViewController?.dismiss(animated: false, completion: nil)
		tabBarVC.selectedIndex = AppDelegate.BrowseTabBarIndex

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
		tabBarVC.selectedIndex = AppDelegate.PinMatchesTabBarIndex

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
		tabBarVC.selectedIndex = AppDelegate.BrowseTabBarIndex

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
		let model = PeerViewModelController.shared.viewModel(of: peerID)
		let idModel = PeereeIdentityViewModelController.viewModel(of: peerID)

		if !model.verified {
			let alertController = UIAlertController(title: NSLocalizedString("Unverified Peer", comment: "Title of the alert which pops up when the user is about to pin an unverified peer"), message: NSLocalizedString("Be careful: the identity of this person is not verified, you may attempt to pin someone malicious!", comment: "Alert message if the user is about to pin someone who did not yet authenticate himself"), preferredStyle: UIDevice.current.iPadOrMac ? .alert : .actionSheet)
			let retryVerifyAction = UIAlertAction(title: NSLocalizedString("Retry verify", comment: "The user wants to retry verifying peer"), style: .`default`) { action in
				PeeringController.shared.interact(with: peerID) { interaction in
					interaction.verify()
				}
			}
			alertController.addAction(retryVerifyAction)
			let actionTitle = String(format: NSLocalizedString("Pin %@", comment: "The user wants to pin the person, whose name is given in the format argument"), model.info.nickname)
			alertController.addAction(UIAlertAction(title: actionTitle, style: .destructive) { action in
				AccountController.use { $0.pin(idModel.id) }
			})
			alertController.addCancelAction()
			alertController.preferredAction = retryVerifyAction
			alertController.present()
		} else if !PeereeIdentityViewModelController.accountExists {
			InAppNotificationController.display(title: NSLocalizedString("Peeree Identity Required", comment: "Title of alert when the user wants to go online but lacks an account and it's creation failed."), message: NSLocalizedString("Tap on 'Profile' to create your Peeree identity.", comment: "The user lacks a Peeree account")) /*{
				(AppDelegate.shared.window?.rootViewController as? UITabBarController)?.selectedIndex = AppDelegate.MeTabBarIndex
			}*/
		} else {
			AccountController.use { $0.pin(idModel.id) }
		}
	}

	static func viewTerms(in viewController: UIViewController) {
		guard let termsURL = URL(string: NSLocalizedString("terms-app-url", comment: "Peeree App Terms of Use URL")) else { return }
		let safariController = SFSafariViewController(url: termsURL)
		if #available(iOS 10.0, *) {
			safariController.preferredControlTintColor = AppTheme.tintColor
		}
		if #available(iOS 11.0, *) {
			safariController.dismissButtonStyle = .done
		}
		viewController.present(safariController, animated: true, completion: nil)
	}

	/// Display the onboarding view controller on top of all other content.
	static func presentOnboarding() {
		let storyboard = UIStoryboard(name:"FirstLaunch", bundle: nil)

		storyboard.instantiateInitialViewController()?.presentInFrontMostViewController(true, completion: nil)
	}

	@objc func toggleNetwork(_ sender: AnyObject) {
		if PeeringController.shared.isBluetoothOn {
			PeeringController.shared.change(peering: !PeerViewModelController.shared.peering)
			AccountController.use { $0.refreshBlockedContent { error in
				InAppNotificationController.display(openapiError: error, localizedTitle: NSLocalizedString("Objectionable Content Refresh Failed", comment: "Title of alert when the remote API call to refresh objectionable portrait hashes failed."))
			} }
			if #available(iOS 13.0, *) { HapticController.playHapticClick() }
		} else {
			open(urlString: UIApplication.openSettingsURLString)
		}
	}
}
