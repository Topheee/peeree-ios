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
			return UIColor(displayP3Red: 21.0/255.0, green: 132.0/255.0, blue: 93.0/255.0, alpha: 1.0)
		} else {
			return UIColor(red: 21.0/255.0, green: 132.0/255.0, blue: 93.0/255.0, alpha: 1.0)
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
class AppDelegate: UIResponder, UIApplicationDelegate, AccountControllerDelegate, PeeringControllerDelegate {
	static let BrowseTabBarIndex = 0
	static let PinMatchesTabBarIndex = 1
	static let MeTabBarIndex = 2
	static var shared: AppDelegate { return UIApplication.shared.delegate as! AppDelegate }

	private let notificationManager = NotificationManager()

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
		notificationManager.initialize()
		
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

		PeeringController.shared.delegate = self
		_ = PinMatchesController.shared
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
				_ = manager.loadResources()
			}
		}
		
		UIApplication.shared.cancelAllLocalNotifications()
	}

	/**
	 *  Stops networking and synchronizes preferences
	 */
	func applicationWillTerminate(_ application: UIApplication) {
		ServerChatController.close()
		PeeringController.shared.peering = false
		UserDefaults.standard.synchronize()
	}
	
	func application(_ application: UIApplication, didReceive notification: UILocalNotification) {
		notificationManager.application(application, didReceive: notification)
	}
	
	func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
		PeeringController.shared.peering = false
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

	// MARK: PeeringControllerDelegate

	func peeringControllerIsReadyToGoOnline() {
		PeeringController.shared.peering = true
	}

	func serverChatLoginFailed(with error: Error) {
		AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Login to Server Chat Failed", comment: "Error message title"))
	}
	
	// MARK: Private Methods
	
	private func setupManualAppearance() {
		UISwitch.appearance().onTintColor = UIAccessibility.isInvertColorsEnabled ? (AppTheme.tintColor.cgColor.inverted().map { UIColor(cgColor: $0) } ?? AppTheme.tintColor) : AppTheme.tintColor
	}
	
	private func setupAppearance() {
		setupManualAppearance()

		if #available(iOS 13.0, *) {
			UINavigationBar.appearance().tintColor = AppTheme.backgroundColor
			let appearance = UINavigationBarAppearance(idiom: .unspecified)
			appearance.configureWithOpaqueBackground()
			appearance.backgroundColor = AppTheme.tintColor
			appearance.backgroundEffect = nil
			appearance.largeTitleTextAttributes = [.foregroundColor: AppTheme.backgroundColor]
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
