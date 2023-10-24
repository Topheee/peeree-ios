//
//  AppDelegate.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import PeereeCore
import PeereeServerChat
import PeereeServer
import PeereeDiscovery

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
class AppDelegate: UIResponder, UIApplicationDelegate {
	static let BrowseTabBarIndex = 0
	static let PinMatchesTabBarIndex = 1
	static let MeTabBarIndex = 2
	static var shared: AppDelegate { return UIApplication.shared.delegate as! AppDelegate }

	/// This is somehow set by the environment...
	var window: UIWindow?
	
	var isActive: Bool = false

	// MARK: UIApplicationDelegate

	/**
	 *  Registers for notifications, presents onboarding on first launch and applies GUI theme
	 */
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		// Configure singletons
		AccountControllerFactory.shared.initialize()
		NotificationManager.shared.initialize()
		UserPeer.instance.delegate = Mediator.shared

		// Global configuration
		setupAppearance()

		_ = PeereeIdentityViewModel.NotificationName.pinStateUpdated.addAnyPeerObserver { (peerID, _) in
			guard PeereeIdentityViewModelController.viewModels[peerID]?.pinState == .pinned else { return }
			
			if #available(iOS 13.0, *) {
				Task {
					await HapticController.shared.playHapticPin()
				}
			}
		}

		// start Bluetooth and server chat, but only if account exists
		AccountControllerFactory.shared.use { ac in
			setup(ac: ac, errorTitle: NSLocalizedString("Login to Chat Server Failed", comment: "Error message title"))
			self.togglePeering()
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

			if #available(iOS 16.0, *) {
				notificationCenter.setBadgeCount(0)
			}
		} else {
			UIApplication.shared.cancelAllLocalNotifications()
		}

		UIApplication.shared.applicationIconBadgeNumber = 0
	}

	/**
	 *  Stops networking and synchronizes preferences
	 */
	func applicationWillTerminate(_ application: UIApplication) {
		ServerChatFactory.use { $0?.closeServerChat() }
		PeeringController.shared.change(peering: false)
		UserDefaults.standard.synchronize()
	}

	func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
		PeeringController.shared.change(peering: false)
	}

	/// MARK: Notifications

	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
		elog(Self.LogTag, "Remote notifications are unavailable: \(error.localizedDescription)")
		InAppNotificationController.display(error: error, localizedTitle: "Notification Registration Failed")
	}

	func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
		ServerChatFactory.use { $0?.configureRemoteNotificationsDeviceToken(deviceToken) }
	}

	func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		completionHandler(.newData)
	}

	// MARK: - Private

	// Log tag.
	private static let LogTag = "AppDelegate"

	// MARK: Methods

	private func setupManualAppearance() {
		UISwitch.appearance().onTintColor = UIAccessibility.isInvertColorsEnabled ? (AppTheme.tintColor.cgColor.inverted().map { UIColor(cgColor: $0) } ?? AppTheme.tintColor) : AppTheme.tintColor
	}

	/// Customize global UI flags.
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

		NotificationCenter.default.addObserver(forName: UIAccessibility.invertColorsStatusDidChangeNotification, object: nil, queue: nil) { (notification) in
			DispatchQueue.main.async { self.setupManualAppearance() }
		}
	}
}
