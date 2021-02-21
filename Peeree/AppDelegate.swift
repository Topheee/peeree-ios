//
//  AppDelegate.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import SafariServices

let wwwHomeURL = NSLocalizedString("https://www.peeree.de/en/index.html", comment: "Peeree Homepage")
let wwwPrivacyPolicyURL = NSLocalizedString("https://www.peeree.de/en/privacy.html", comment: "Peeree Privacy Policy")

struct VisualTheme {
	var tintColor: UIColor {
		if #available(iOS 10, *) {
			return UIColor(displayP3Red: 22.0/255.0, green: 145.0/255.0, blue: 101.0/255.0, alpha: 1.0)
		} else {
			return UIColor(red: 22.0/255.0, green: 145.0/255.0, blue: 101.0/255.0, alpha: 1.0)
		}
	}
	var backgroundColor: UIColor {
		if #available(iOS 13, *) {
			return UIColor.systemBackground
		} else {
			return UIColor.white
		}
	}
}
let AppTheme = VisualTheme()

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, AccountControllerDelegate {
	static let PeerIDKey = "PeerIDKey"
	static let BundleID = Bundle.main.bundleIdentifier ?? "de.peeree"
	
	static var shared: AppDelegate { return UIApplication.shared.delegate as! AppDelegate }
	
	static func display(networkError: Error, localizedTitle: String, furtherDescription: String? = nil) {
		var notificationAction: (() -> Void)? = nil
		var errorMessage: String
		if let errorResponse = networkError as? ErrorResponse {
			let httpErrorMessage = NSLocalizedString("HTTP error %d.", comment: "Error message for HTTP status codes")
			switch errorResponse {
			case .parseError(_):
				errorMessage = NSLocalizedString("Malformed server response.", comment: "Message of network error")
			case .httpError(let code, _):
				errorMessage = String(format: httpErrorMessage, code)
				if code == 403 {
					errorMessage = errorMessage + NSLocalizedString(" Something went wrong with the authentication. Please try again in a minute.", comment: "Appendix to message")
				}
			case .sessionTaskError(let code, _, let theError):
				errorMessage = "\(String(format: httpErrorMessage, code ?? -1)): \(theError.localizedDescription)"
			case .offline:
				errorMessage = NSLocalizedString("The network appears to be offline. You may need to grant Peeree access to it.", comment: "Message of network offline error")
				notificationAction = { UIApplication.shared.openURL(URL(string: UIApplication.openSettingsURLString)!) }
			}
		} else {
			errorMessage = networkError.localizedDescription
		}
		
		if furtherDescription != nil {
			errorMessage += "\n\(furtherDescription!)"
		}
		
		InAppNotificationViewController.presentGlobally(title: localizedTitle, message: errorMessage, isNegative: true, tapAction: notificationAction)
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
	
	/// This is somehow set by the environment...
	var window: UIWindow?
	
	var isActive: Bool = false
	private var onboardingPresented: Bool = false

	/**
	 *  Registers for notifications, presents onboarding on first launch and applies GUI theme
	 */
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		setupAppearance()
		
		AccountController.shared.delegate = self
		
		_ = PeeringController.Notifications.peerAppeared.addPeerObserver { peerID, notification  in
			let again = notification.userInfo?[PeeringController.NotificationInfoKey.again.rawValue] as? Bool
			self.peerAppeared(peerID, again: again ?? false)
		}
		
		_ = PeeringController.Notifications.peerDisappeared.addPeerObserver { peerID, _  in
			self.peerDisappeared(peerID)
		}
		
		_ = AccountController.Notifications.pinMatch.addPeerObserver { peerID, _  in
			guard let peer = PeeringController.shared.manager(for: peerID).peerInfo else {
				assertionFailure()
				return
			}
			
			self.pinMatchOccured(peer)
		}
		
		_ = PeerManager.Notifications.messageReceived.addPeerObserver { peerID, _  in
			self.messageReceived(from: peerID)
		}
		
		_ = PeeringController.Notifications.connectionChangedState.addObserver { notification in
			UIApplication.shared.registerUserNotificationSettings(UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil))
		}
		
		NotificationCenter.default.addObserver(forName: UIAccessibility.invertColorsStatusDidChangeNotification, object: nil, queue: OperationQueue.main) { (notification) in
			self.setupManualAppearance()
		}
		_ = AccountController.Notifications.pinned.addObserver { (_) in
			if #available(iOS 13.0, *) { HapticController.playHapticPin() }
		}

		// reinstantiate CBManagers if there where some
		// TEST this probably will lead to get always online after the app was terminated once after going online as the central manager is always non-nil, so maybe only checck peripheralManager in the if statement
		let restoredCentralManagerIDs = launchOptions?[.bluetoothCentrals] as? [String]
		let restoredPeripheralManagerIDs = launchOptions?[.bluetoothPeripherals] as? [String]
		if restoredCentralManagerIDs?.count ?? 0 > 0 || restoredPeripheralManagerIDs?.count ?? 0 > 0 {
			PeeringController.shared.peering = true
		}
		
		return true
	}

	func applicationWillResignActive(_ application: UIApplication) {
		// TODO e.g., when in find view, stop reading rssi (if it doesn't already get stop by viewWillDisappear)
	}

	func applicationDidEnterBackground(_ application: UIApplication) {
		// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
		// If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
		isActive = false
	}

	func applicationWillEnterForeground(_ application: UIApplication) {
		// Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
	}

	func applicationDidBecomeActive(_ application: UIApplication) {
		// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
		isActive = true
		
		if UserDefaults.standard.object(forKey: UserPeerManager.PrefKey) == nil {
			if !onboardingPresented {
				onboardingPresented = true
				// this is the first launch of the app, so we show the first launch UI
				let storyboard = UIStoryboard(name:"FirstLaunch", bundle: nil)
				
				window?.rootViewController?.present(storyboard.instantiateInitialViewController()!, animated: false, completion: nil)
			}
		} else {
			for peerID in PeeringController.shared.remote.availablePeers {
				let manager = PeeringController.shared.manager(for: peerID)
				guard let peer = manager.peerInfo, BrowseFilterSettings.shared.check(peer: peer) else { continue }
				_ = manager.loadPicture()
			}
		}
		
		UIApplication.shared.cancelAllLocalNotifications()
	}

	/**
	 *  Stops networking and synchronizes preferences
	 */
	func applicationWillTerminate(_ application: UIApplication) {
		PeeringController.shared.peering = false
		UserDefaults.standard.synchronize()
	}
	
	func application(_ application: UIApplication, didReceive notification: UILocalNotification) {
		guard application.applicationState == .inactive else { return }
		guard let peerIDData = notification.userInfo?[AppDelegate.PeerIDKey] as? Data else { return }
		guard let peerID = NSKeyedUnarchiver.unarchiveObject(with: peerIDData) as? PeerID else { return }
		
		show(peerID: peerID)
	}
	
	func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
		PeeringController.shared.peering = false
	}
	
	func show(peerID: PeerID) {
		guard let browseNavVC = window?.rootViewController as? UINavigationController else { return }
		
		browseNavVC.presentedViewController?.dismiss(animated: false, completion: nil)
		
		var browseVC: BrowseViewController? = nil
		for vc in browseNavVC.viewControllers {
			if vc is BrowseViewController {
				browseVC = vc as? BrowseViewController
			} else if let personVC = vc as? PersonDetailViewController {
				guard personVC.peerManager.peerID != peerID else { return }
			}
		}
		browseVC?.performSegue(withIdentifier: BrowseViewController.ViewPeerSegueID, sender: peerID)
	}
	
	func find(peer: PeerInfo) {
		guard let browseNavVC = window?.rootViewController as? UINavigationController else { return }
		
		browseNavVC.presentedViewController?.dismiss(animated: false, completion: nil)
		
		var _browseVC: BrowseViewController? = nil
		var _personVC: PersonDetailViewController? = nil
		for vc in browseNavVC.viewControllers {
			if vc is BrowseViewController {
				_browseVC = vc as? BrowseViewController
			} else if let somePersonVC = vc as? PersonDetailViewController {
				if somePersonVC.peerManager.peerID == peer.peerID {
					_personVC = somePersonVC
				}
			} else if let someBeaconVC = vc as? BeaconViewController {
				guard someBeaconVC.peerManager?.peerInfo != peer else { return }
			}
		}
		
		if let personVC = _personVC {
			personVC.performSegue(withIdentifier: PersonDetailViewController.beaconSegueID, sender: nil)
		} else if let browseVC = _browseVC {
			guard let personVC = browseVC.storyboard?.instantiateViewController(withIdentifier: PersonDetailViewController.storyboardID) as? PersonDetailViewController,
				let findVC = browseVC.storyboard?.instantiateViewController(withIdentifier: BeaconViewController.storyboardID) as? BeaconViewController else { return }
			let manager = PeeringController.shared.manager(for: peer.peerID)
			personVC.peerManager = manager
			browseNavVC.pushViewController(personVC, animated: false)
			findVC.peerManager = manager
			browseNavVC.pushViewController(findVC, animated: false)
		}
	}
	
	static func requestPin(of peer: PeerInfo) {
		let manager = PeeringController.shared.manager(for: peer.peerID)
		if !manager.verified {
			let alertController = UIAlertController(title: NSLocalizedString("Unverified Peer", comment: "Title of the alert which pops up when the user is about to pin an unverified peer"), message: NSLocalizedString("Be careful: the identity of this person is not verified, you may attempt to pin someone malicious!", comment: "Alert message if the user is about to pin someone who did not yet authenticate himself"), preferredStyle: .actionSheet)
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
	
	// MARK: AccountControllerDelegate
	func pin(of peerID: PeerID, failedWith error: Error) {
		AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Pin Failed", comment: "Title of in-app error notification"))
	}
	
	func publicKeyMismatch(of peerID: PeerID) {
		let peerDescription = PeeringController.shared.manager(for: peerID).peerInfo?.nickname ?? peerID.uuidString
		let message = String(format: NSLocalizedString("The identity of %@ is invalid.", comment: "Message of Possible Malicious Peer alert"), peerDescription)
		InAppNotificationViewController.presentGlobally(title: NSLocalizedString("Possible Malicious Peer", comment: "Title of public key mismatch in-app notification"), message: message)
	}
	
	func sequenceNumberResetFailed(error: ErrorResponse) {
		AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Resetting Server Nonce Failed", comment: "Title of sequence number reset failure alert"), furtherDescription: NSLocalizedString("The server nonce is used to secure your connection.", comment: "Further description of Resetting Server Nonce Failed alert"))
	}
	
	// MARK: Private Methods
	
	/// shows an in-app or system (local) notification related to a peer
	private func displayPeerRelatedNotification(title: String, body: String, peerID: PeerID, sufficientCondition: Bool) {
		if isActive && sufficientCondition {
			InAppNotificationViewController.presentGlobally(title: title, message: body, isNegative: false) { self.show(peerID: peerID) }
		} else {
			if #available(iOS 10, *) {
				let center = UNUserNotificationCenter.current()
				center.requestAuthorization(options: [.alert, .sound]) { granted, error in
					// Enable or disable features based on authorization.
					guard error == nil else {
						NSLog("ERROR: Error requesting user notification authorization: \(error!.localizedDescription)")
						return
					}
					if granted {
						let content = UNMutableNotificationContent()
						content.title = title
						content.body = body
						content.sound = UNNotificationSound.default
						content.userInfo = [AppDelegate.PeerIDKey : NSKeyedArchiver.archivedData(withRootObject: peerID)]
						center.add(UNNotificationRequest(identifier: peerID.uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))) { (_error) in
							if let error = _error {
								NSLog("ERROR: Scheduling local notification failed: \(error.localizedDescription)")
							}
						}
					}
				}
			} else {
				let note = UILocalNotification()
				note.alertTitle = title
				note.alertBody = body
				note.userInfo = [AppDelegate.PeerIDKey : NSKeyedArchiver.archivedData(withRootObject: peerID)]
				UIApplication.shared.presentLocalNotificationNow(note)
			}
		}
	}
	
	private func messageReceived(from peerID: PeerID) {
		let manager = PeeringController.shared.manager(for: peerID)
		guard let peer = manager.peerInfo, let message = manager.transcripts.last?.message else { return }
		let titleFormat = NSLocalizedString("Message from %@.", comment: "Notification alert body when a message is received.")
		let title = String(format: titleFormat, peer.nickname)
		displayPeerRelatedNotification(title: title, body: message, peerID: peerID, sufficientCondition: ((window?.rootViewController as? UINavigationController)?.visibleViewController as? PersonDetailViewController)?.peerManager.peerID != peerID)
	}
	
	private func peerAppeared(_ peerID: PeerID, again: Bool) {
		guard !again, let peer = PeeringController.shared.manager(for: peerID).peerInfo,
			BrowseFilterSettings.shared.check(peer: peer) else { return }
		if isActive {
			_ = PeeringController.shared.manager(for: peerID).loadPicture()
		}
		let alertBodyFormat = NSLocalizedString("Found %@.", comment: "Notification alert body when a new peer was found on the network.")
		displayPeerRelatedNotification(title: String(format: alertBodyFormat, peer.nickname), body: "", peerID: peerID, sufficientCondition: ((window?.rootViewController as? UINavigationController)?.visibleViewController as? BrowseViewController) == nil)
	}
	
	private func peerDisappeared(_ peerID: PeerID) {
		// ignored
	}
	
	private func pinMatchOccured(_ peer: PeerInfo) {
		if isActive {
			let pinMatchVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: PinMatchViewController.StoryboardID) as! PinMatchViewController
			pinMatchVC.displayedPeer = peer
			DispatchQueue.main.async {
				if let presentingVC = self.window?.rootViewController?.presentedViewController {
					// if Me screen is currently presented
					presentingVC.present(pinMatchVC, animated: true, completion: nil)
				} else {
					self.window?.rootViewController?.present(pinMatchVC, animated: true, completion: nil)
				}
			}
		} else {
			let alertBodyFormat = NSLocalizedString("Pin Match with %@!", comment: "Notification alert body when a pin match occured.")
			let alertBody = String(format: alertBodyFormat, peer.nickname)
			let applicationIconBadgeNumber = UIApplication.shared.applicationIconBadgeNumber + 1
			let userInfo = [AppDelegate.PeerIDKey : NSKeyedArchiver.archivedData(withRootObject: peer.peerID)]
			if #available(iOS 10, *) {
				let center = UNUserNotificationCenter.current()
				center.requestAuthorization(options: [.alert, .sound]) { granted, error in
					// Enable or disable features based on authorization.
					guard error == nil else {
						NSLog("ERROR: Error requesting user notification authorization: \(error!.localizedDescription)")
						return
					}
					if granted {
						let content = UNMutableNotificationContent()
						content.body = alertBody
						content.sound = UNNotificationSound.default
						content.userInfo = userInfo
						center.add(UNNotificationRequest(identifier: peer.peerID.uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))) { (_error) in
							if let error = _error {
								NSLog("ERROR: Scheduling local notification failed: \(error.localizedDescription)")
							}
						}
					}
				}
			} else {
				let note = UILocalNotification()
				note.alertBody = alertBody
				note.applicationIconBadgeNumber = applicationIconBadgeNumber
				note.userInfo = userInfo
				UIApplication.shared.presentLocalNotificationNow(note)
			}
		}
	}
	
	private func setupManualAppearance() {
		UISwitch.appearance().onTintColor = UIAccessibility.isInvertColorsEnabled ? (AppTheme.tintColor.cgColor.inverted().map { UIColor(cgColor: $0) } ?? AppTheme.tintColor) : AppTheme.tintColor
	}
	
	private func setupAppearance() {
		setupManualAppearance()

		if #available(iOS 13.0, *) {
			UINavigationBar.appearance().tintColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)
			let appearance = UINavigationBarAppearance()
			appearance.configureWithOpaqueBackground()
			appearance.backgroundColor = #colorLiteral(red: 0.0862745098, green: 0.568627451, blue: 0.3960784314, alpha: 1)
			appearance.largeTitleTextAttributes = [.foregroundColor: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)]
			UINavigationBar.appearance().standardAppearance = appearance
			UINavigationBar.appearance().compactAppearance = appearance
			UINavigationBar.appearance().scrollEdgeAppearance = appearance
		} else {
			UINavigationBar.appearance().tintColor = AppTheme.backgroundColor
			UINavigationBar.appearance().barTintColor = AppTheme.tintColor
			UITableView.appearance().separatorColor = UIColor(white: 0.3, alpha: 1.0)
		}
		
		UIActivityIndicatorView.appearance().color = AppTheme.tintColor
		UIPageControl.appearance().pageIndicatorTintColor = AppTheme.tintColor.withAlphaComponent(0.65)
		UIPageControl.appearance().currentPageIndicatorTintColor = AppTheme.tintColor
	}
}
