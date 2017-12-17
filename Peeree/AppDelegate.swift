//
//  AppDelegate.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

struct Theme {
    let globalTintRed: CGFloat
    let globalTintGreen: CGFloat
    let globalTintBlue: CGFloat
    let globalTintColor: UIColor
    let globalBackgroundRed: CGFloat
    let globalBackgroundGreen: CGFloat
    let globalBackgroundBlue: CGFloat
    let globalBackgroundColor: UIColor
    let barBackgroundColor : UIColor
    let barTintColor : UIColor
    
    init(globalTint: (r:CGFloat, g:CGFloat, b:CGFloat), barTint: (r:CGFloat, g:CGFloat, b:CGFloat), globalBackground: (r:CGFloat, g:CGFloat, b:CGFloat), barBackground: (r:CGFloat, g:CGFloat, b:CGFloat)) {
        self.globalTintRed = globalTint.r
        self.globalTintGreen = globalTint.g
        self.globalTintBlue = globalTint.b
        self.globalTintColor = UIColor(red: self.globalTintRed, green: self.globalTintGreen, blue: self.globalTintBlue, alpha: 1.0)
        self.globalBackgroundRed = globalBackground.r
        self.globalBackgroundGreen = globalBackground.g
        self.globalBackgroundBlue = globalBackground.b
        self.globalBackgroundColor = UIColor(red: globalBackgroundRed, green: globalBackgroundGreen, blue: globalBackgroundBlue, alpha: 1.0)
        self.barBackgroundColor = UIColor(red: barBackground.r, green: barBackground.g, blue: barBackground.b, alpha: 1.0)
        barTintColor = UIColor(red: barTint.r, green: barTint.g, blue: barTint.b, alpha: 1.0)
    }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, AccountControllerDelegate {
    static private let PrefSkipOnboarding = "peeree-prefs-skip-onboarding"
    static let PeerIDKey = "PeerIDKey"
	
    static var shared: AppDelegate { return UIApplication.shared.delegate as! AppDelegate }
    
    static func display(networkError: Error, localizedTitle: String, furtherDescription: String? = nil) {
        var errorMessage: String
        if let errorResponse = networkError as? ErrorResponse {
            switch errorResponse {
            case .parseError(_):
                errorMessage = NSLocalizedString("Malformed server response.", comment: "Message of network error")
            case .httpError(let code, _):
                errorMessage = "HTTP error \(code)"
            case .sessionTaskError(let code, _, let theError):
                errorMessage = "HTTP error \(code ?? -1): \(theError.localizedDescription)"
            }
        } else {
            errorMessage = networkError.localizedDescription
        }
        
        if furtherDescription != nil {
            errorMessage += "\n\(furtherDescription!)"
        }
        
        InAppNotificationViewController.shared.presentGlobally(title: localizedTitle, message: errorMessage)
    }
    
    let theme = Theme(globalTint: (22/255, 145/255, 101/255), barTint: (22/255, 145/255, 101/255), globalBackground: (255/255, 255/255, 255/255), barBackground: (255/255, 255/255, 255/255)) //white with green
    
    /// This is somehow set by the environment...
    var window: UIWindow?
    
	var isActive: Bool = false

    /**
     *  Registers for notifications, presents onboarding on first launch and applies GUI theme
     */
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
		UserDefaults.standard.register(defaults: [InAppPurchaseController.PinPointPrefKey : InAppPurchaseController.InitialPinPoints])
        
        setupAppearance()
        
        AccountController.shared.delegate = self
        
        _ = PeeringController.Notifications.peerAppeared.addObserver { notification in
            guard let again = notification.userInfo?[PeeringController.NotificationInfoKey.again.rawValue] as? Bool else { return }
            guard let peerID = notification.userInfo?[PeeringController.NotificationInfoKey.peerID.rawValue] as? PeerID else { return }
            guard let peer = PeeringController.shared.remote.getPeerInfo(of: peerID) else { return }

            self.peerAppeared(peer, again: again)
        }
        
        _ = PeeringController.Notifications.peerDisappeared.addObserver { notification in
            guard let peerID = notification.userInfo?[PeeringController.NotificationInfoKey.peerID.rawValue] as? PeerID else { return }
            
            self.peerDisappeared(peerID)
        }
        
        _ = AccountController.Notifications.pinMatch.addObserver { notification in
            guard let peerID = notification.userInfo?[PeeringController.NotificationInfoKey.peerID.rawValue] as? PeerID else { return }
            guard let peer = PeeringController.shared.remote.getPeerInfo(of: peerID) else {
                assertionFailure()
                return
            }
            
            self.pinMatchOccured(peer)
        }
        
        _ = PeeringController.Notifications.connectionChangedState.addObserver { notification in
            if UIApplication.instancesRespond(to: #selector(UIApplication.registerUserNotificationSettings(_:))) {
                //only ask on iOS 8 or later
                UIApplication.shared.registerUserNotificationSettings(UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil))
            }
            
            guard let topVC = self.window?.rootViewController as? UITabBarController else { return }
            guard let browseItem = topVC.tabBar.items?.first else { return }
            
            browseItem.image = PeeringController.shared.peering ? #imageLiteral(resourceName: "RadarTemplateFilled") : #imageLiteral(resourceName: "RadarTemplate")
            browseItem.selectedImage = browseItem.image
        }

        // reinstantiate CBManagers if there where some
        // TEST this probably will lead to get always online after the app was terminated once after going online as the central manager is always non-nil, so maybe only checck peripheralManager in the if statement
        let restoredCentralManagerIDs = launchOptions?[UIApplicationLaunchOptionsKey.bluetoothCentrals] as? [String]
        let restoredPeripheralManagerIDs = launchOptions?[UIApplicationLaunchOptionsKey.bluetoothPeripherals] as? [String]
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
        
        if !UserDefaults.standard.bool(forKey: AppDelegate.PrefSkipOnboarding) {
            // this is the first launch of the app, so we show the first launch UI
            let storyboard = UIStoryboard(name:"FirstLaunch", bundle: nil)
            
            window?.rootViewController?.present(storyboard.instantiateInitialViewController()!, animated: false, completion: nil)
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
        guard let peerInfo = PeeringController.shared.remote.getPeerInfo(of: peerID) else { return }
        
        show(peer: peerInfo)
    }
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        PeeringController.shared.peering = false
        InAppPurchaseController.shared.clearCache()
    }
    
    func finishIntroduction() {
        UserDefaults.standard.set(true, forKey: AppDelegate.PrefSkipOnboarding)
    }
    
    func show(peer: PeerInfo) {
        guard let rootTabBarController = window?.rootViewController as? UITabBarController else { return }
        guard let browseNavVC = rootTabBarController.viewControllers?[0] as? UINavigationController else { return }
        
        rootTabBarController.selectedIndex = 0
        var browseVC: BrowseViewController? = nil
        for vc in browseNavVC.viewControllers {
            if vc is BrowseViewController {
                browseVC = vc as? BrowseViewController
            } else if let personVC = vc as? PersonDetailViewController {
                guard personVC.displayedPeerInfo != peer else { return }
            }
        }
        browseVC?.performSegue(withIdentifier: BrowseViewController.ViewPeerSegueID, sender: peer)
    }
    
    func find(peer: PeerInfo) {
        guard let rootTabBarController = window?.rootViewController as? UITabBarController else { return }
        guard let browseNavVC = rootTabBarController.viewControllers?[0] as? UINavigationController else { return }
        
        rootTabBarController.selectedIndex = 0
        
        var _browseVC: BrowseViewController? = nil
        var _personVC: PersonDetailViewController? = nil
        for vc in browseNavVC.viewControllers {
            if vc is BrowseViewController {
                _browseVC = vc as? BrowseViewController
            } else if let somePersonVC = vc as? PersonDetailViewController {
                if somePersonVC.displayedPeerInfo == peer {
                    _personVC = somePersonVC
                }
            } else if let someBeaconVC = vc as? BeaconViewController {
                guard someBeaconVC.searchedPeer != peer else { return }
            }
        }
        
        if let personVC = _personVC {
            personVC.performSegue(withIdentifier: PersonDetailViewController.beaconSegueID, sender: nil)
        } else if let browseVC = _browseVC {
            guard let personVC = browseVC.storyboard?.instantiateViewController(withIdentifier: PersonDetailViewController.storyboardID) as? PersonDetailViewController,
                let findVC = browseVC.storyboard?.instantiateViewController(withIdentifier: BeaconViewController.storyboardID) as? BeaconViewController else { return }
            personVC.displayedPeerInfo = peer
            browseNavVC.pushViewController(personVC, animated: false)
            findVC.searchedPeer = peer
            browseNavVC.pushViewController(findVC, animated: false)
        }
    }
    
    static func requestPin(of peer: PeerInfo) {
        let title = NSLocalizedString("Spend Pin Points", comment: "Title of the alert which pops up when the user is about to spend in-app currency")
        var message: String
        var actions: [UIAlertAction] = [UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)]
        
        if InAppPurchaseController.shared.availablePinPoints >= InAppPurchaseController.PinCosts {
            message = NSLocalizedString("You have %d pin points available.", comment: "Alert message if the user is about to spend in-app currency and has enough of it in his pocket")
            message = String(format: message, InAppPurchaseController.shared.availablePinPoints)
            if !peer.verified {
                message = "\(message) \(NSLocalizedString("But be careful: the identity of the user is not verified, ou may be pinning someone else!", comment: "Alert message if the user is about to pin someone who did not yet authenticate himself"))"
                actions.append(UIAlertAction(title: NSLocalizedString("Retry verify", comment: "The user wants to retry verifying peer"), style: .default) { action in
                    PeeringController.shared.remote.verify(peer.peerID)
                })
            }
            let actionTitle = String(format: NSLocalizedString("Spend %d", comment: "The user accepts to spend pin points for this action"), InAppPurchaseController.PinCosts)
            actions.append(UIAlertAction(title: actionTitle, style: peer.verified ? .default : .destructive) { action in
                AccountController.shared.pin(peer)
            })
        } else {
            message = NSLocalizedString("You do not have enough pin points available.", comment: "Alert message if the user is about to buy something and has not enough of in-app money in his pocket")
            actions.append(UIAlertAction(title: NSLocalizedString("Visit Shop", comment: "Title of action which opens the shop view"), style: .default) { action in
                guard let rootTabBarController = UIApplication.shared.keyWindow?.rootViewController as? UITabBarController else { return }
                
                rootTabBarController.selectedIndex = 2
            })
        }
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        for action in actions {
            alertController.addAction(action)
        }
        alertController.present(nil)
    }
    
    // MARK: AccountControllerDelegate
    
    func publicKeyMismatch(of peerID: PeerID) {
        let message = String(format: NSLocalizedString("The identity of %@ is invalid.", comment: "Message of Possibly Malicious Peer alert"), peerID.uuidString)
        InAppNotificationViewController.shared.presentGlobally(title: NSLocalizedString("Possibly Malicious Peer", comment: "Title of public key mismatch in-app notification"), message: message)
    }
    
    func sequenceNumberResetFailed(error: ErrorResponse) {
        AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Resetting Server Nonce Failed", comment: "Title of sequence number reset failure alert"), furtherDescription: NSLocalizedString("The server nonce is used to secure your connection.", comment: "Further description of Resetting Server Nonce Failed alert"))
    }
    
    // MARK: Private Methods
    
    private func peerAppeared(_ peer: PeerInfo, again: Bool) {
        guard BrowseFilterSettings.shared.check(peer: peer) else { return }
		if !isActive {
            guard !again else { return }
            
			let note = UILocalNotification()
            let alertBodyFormat = NSLocalizedString("Found %@.", comment: "Notification alert body when a new peer was found on the network.")
			note.alertBody = String(format: alertBodyFormat, peer.nickname)
            note.userInfo = [AppDelegate.PeerIDKey : NSKeyedArchiver.archivedData(withRootObject: peer.peerID)]
			UIApplication.shared.presentLocalNotificationNow(note)
        } else if BrowseViewController.instance == nil {
            updateNewPeerBadge(by: 1)
		}
	}
	
	private func peerDisappeared(_ peerID: PeerID) {
        updateNewPeerBadge(by: -1)
	}
    
    private func pinMatchOccured(_ peer: PeerInfo) {
        if isActive {
            setPinMatchBadge()
            let pinMatchVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: PinMatchViewController.StoryboardID) as! PinMatchViewController
            pinMatchVC.displayedPeer = peer
            DispatchQueue.main.async {
                (self.window?.rootViewController as? UITabBarController)?.selectedViewController?.present(pinMatchVC, animated: true, completion: nil)
            }
        } else {
            let note = UILocalNotification()
            let alertBodyFormat = NSLocalizedString("Pin match with %@!", comment: "Notification alert body when a pin match occured.")
            note.alertBody = String(format: alertBodyFormat, peer.nickname)
            note.applicationIconBadgeNumber = UIApplication.shared.applicationIconBadgeNumber + 1
            note.userInfo = [AppDelegate.PeerIDKey : NSKeyedArchiver.archivedData(withRootObject: peer.peerID)]
            UIApplication.shared.presentLocalNotificationNow(note)
        }
    }
    
    private func setPinMatchBadge() {
        guard let rootTabBarController = window?.rootViewController as? UITabBarController else { return }
        
        rootTabBarController.tabBar.items?[0].badgeValue = NSLocalizedString("Pin Match", comment: "The name of the event when two peers pinned each other.")
    }
    
    private func updateNewPeerBadge(by: Int) {
        guard let tabBarItem = (window?.rootViewController as? UITabBarController)?.tabBar.items?[0] else { return }
        
        var newBadgeValue: Int = by
        if let oldBadgeValue = tabBarItem.badgeValue,
            let oldValue = Int(oldBadgeValue) {
            
            newBadgeValue += oldValue
        }
        
        tabBarItem.badgeValue = newBadgeValue <= 0 ? nil : String(newBadgeValue)
    }
    
    private func setupAppearance() {
        RootView.appearance().tintColor = theme.globalTintColor
        RootView.appearance().backgroundColor = theme.globalBackgroundColor
        
        // iOS 11 UINavigationBar ButtonItem Fix
        if #available(iOS 11, *) {
            UIButton.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).tintColor = theme.barBackgroundColor
        }
        
        UINavigationBar.appearance().tintColor = theme.barBackgroundColor // theme.barTintColor
        UINavigationBar.appearance().barTintColor = theme.barTintColor
        UINavigationBar.appearance().barStyle = .black
        
        UITabBar.appearance().tintColor = theme.barTintColor
        UITabBar.appearance().backgroundColor = theme.barBackgroundColor
        
        UITableViewCell.appearance().backgroundColor = theme.globalBackgroundColor
        UITableView.appearance().separatorColor = UIColor(white: 0.3, alpha: 1.0)
        UITableView.appearance().backgroundColor = theme.globalBackgroundColor
        
        UITableViewCell.appearance().backgroundColor = UIColor(white: 0.0, alpha: 0.0)
        UITextView.appearance().backgroundColor = UIColor(white: 0.0, alpha: 0.0)
        
        UIToolbar.appearance().tintColor = theme.globalTintColor
        
        UIActivityIndicatorView.appearance().color = theme.globalTintColor
        UIStackView.appearance().tintColor = theme.globalTintColor
        
        UIPageControl.appearance().pageIndicatorTintColor = theme.globalTintColor.withAlphaComponent(0.65)
        UIPageControl.appearance().currentPageIndicatorTintColor = theme.globalTintColor
        
        UIWindow.appearance().tintColor = theme.globalTintColor
    }
}
