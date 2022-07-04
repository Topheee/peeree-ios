//
//  AppDelegate.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

let wwwHomeURL = NSLocalizedString("https://www.peeree.de/en/index.html", comment: "Peeree Homepage")
let wwwPrivacyPolicyURL = NSLocalizedString("https://www.peeree.de/en/privacy.html", comment: "Peeree Privacy Policy")

struct VisualTheme {
	let tintColor = UIColor(red: 21.0/256.0, green: 132.0/256.0, blue: 93.0/256.0, alpha: 1.0)

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
class AppDelegate: UIResponder, UIApplicationDelegate, AccountControllerDelegate, PeeringControllerDelegate, ServerChatDelegate {
	static let BrowseTabBarIndex = 0
	static let PinMatchesTabBarIndex = 1
	static let MeTabBarIndex = 2
	static var shared: AppDelegate { return UIApplication.shared.delegate as! AppDelegate }

	private let notificationManager = NotificationManager()

	/// This is somehow set by the environment...
	var window: UIWindow?
	
	var isActive: Bool = false

	// MARK: UIApplicationDelegate

	/**
	 *  Registers for notifications, presents onboarding on first launch and applies GUI theme
	 */
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		// Observe singletons
		ServerChatFactory.delegate = self
		AccountController.delegate = self
		PeeringController.shared.delegate = self

		// Global configuration
		setupAppearance()
		configureServerChat()

		notificationManager.initialize()
		
		NotificationCenter.default.addObserver(forName: UIAccessibility.invertColorsStatusDidChangeNotification, object: nil, queue: OperationQueue.main) { (notification) in
			self.setupManualAppearance()
		}
		_ = PeereeIdentityViewModel.NotificationName.pinStateUpdated.addAnyPeerObserver { (peerID, _) in
			guard PeereeIdentityViewModelController.viewModels[peerID]?.pinState == .pinned else { return }
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

		if #available(iOS 10.0, *) {
			let notificationCenter = UNUserNotificationCenter.current()
			notificationCenter.removeAllPendingNotificationRequests()
			notificationCenter.removeAllDeliveredNotifications()
		} else {
			UIApplication.shared.cancelAllLocalNotifications()
		}

		UIApplication.shared.applicationIconBadgeNumber = 0
	}

	/**
	 *  Stops networking and synchronizes preferences
	 */
	func applicationWillTerminate(_ application: UIApplication) {
		ServerChatFactory.close()
		PeeringController.shared.peering = false
		UserDefaults.standard.synchronize()
	}

	func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
		PeeringController.shared.peering = false
	}

	/// MARK: Notifications
	
	func application(_ application: UIApplication, didReceive notification: UILocalNotification) {
		notificationManager.application(application, didReceive: notification)
	}

	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
		elog("Remote notifications are unavailable: \(error.localizedDescription)")
		InAppNotificationController.display(error: error, localizedTitle: "Notification Registration Failed")
	}

	func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
		ServerChatFactory.remoteNotificationsDeviceToken = deviceToken
		ServerChatFactory.getOrSetupInstance(onlyLogin: true) { result in
			switch result {
			case .failure(let serverChatError):
				switch serverChatError {
				case .identityMissing:
					// ignored
					break
				default:
					InAppNotificationController.display(serverChatError: serverChatError, localizedTitle: "Remote Notification Registration Failed")
				}

			case .success(let serverChatController):
				serverChatController.configurePusher(deviceToken: deviceToken)
			}
		}
	}

	func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		completionHandler(.newData)
	}

	// MARK: AccountControllerDelegate
	func pin(of peerID: PeerID, failedWith error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Pin Failed", comment: "Title of in-app error notification"))
	}
	
	func publicKeyMismatch(of peerID: PeerID) {
		DispatchQueue.main.async {
			let name = PeerViewModelController.viewModel(of: peerID).info.nickname
			let message = String(format: NSLocalizedString("The identity of %@ is invalid.", comment: "Message of Possible Malicious Peer alert"), name)
			let error = createApplicationError(localizedDescription: message)
			InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Possible Malicious Peer", comment: "Title of public key mismatch in-app notification"))
		}
	}
	
	func sequenceNumberResetFailed(error: ErrorResponse) {
		InAppNotificationController.display(openapiError: error, localizedTitle: NSLocalizedString("Resetting Server Nonce Failed", comment: "Title of sequence number reset failure alert"), furtherDescription: NSLocalizedString("The server nonce is used to secure your connection.", comment: "Further description of Resetting Server Nonce Failed alert"))
	}

	// MARK: PeeringControllerDelegate

	func peeringControllerIsReadyToGoOnline() {
		AccountController.use { _ in PeeringController.shared.peering = true }
	}

	func encodingPeersFailed(with error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Encoding Recent Peers Failed", comment: "Low-level error"))
	}

	func decodingPeersFailed(with error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Decoding Recent Peers Failed", comment: "Low-level error"))
	}

	func serverChatLoginFailed(with error: ServerChatError) {
		InAppNotificationController.display(serverChatError: error, localizedTitle: NSLocalizedString("Login to Server Chat Failed", comment: "Error message title"))
	}

	// MARK: ServerChatControllerDelegate

	func configurePusherFailed(_ error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Push Notifications Unavailable", comment: "Title of alert."))
	}

	func cannotJoinRoom(_ error: Error) {
		InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Cannot Join Room", comment: "Title of alert."))
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
