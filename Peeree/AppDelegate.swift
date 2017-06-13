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
class AppDelegate: UIResponder, UIApplicationDelegate {
    static private let PrefSkipOnboarding = "peeree-prefs-skip-onboarding"
    static let PeerIDKey = "PeerIDKey"
	
    static var shared: AppDelegate { return UIApplication.shared.delegate as! AppDelegate }
    
    static func display(networkError: Error, localizedTitle: String, furtherDescription: String? = nil) {
        DispatchQueue.main.async {
            var errorMessage: String
            if let errorResponse = networkError as? ErrorResponse {
                switch errorResponse {
                case .Error(let code, _, let theError):
                    print(code)
                    errorMessage = theError.localizedDescription
                    //                    if (theError as NSError).code == NSURLErrorSecureConnectionFailed {
                    //                        print("untrusted")
                    //                    }
                }
            } else {
                errorMessage = networkError.localizedDescription
            }
            
            if furtherDescription != nil {
                errorMessage += "\n\(furtherDescription!)"
            }
            
            let alert = UIAlertController(title: localizedTitle, message: errorMessage, preferredStyle: .alert)
            //                alert.addAction(UIAlertAction(title: ), style: .destructive, handler: proceedHandler))
            alert.addAction(UIAlertAction(title: Bundle.main.localizedString(forKey: "Cancel", value: nil, table: nil), style: .cancel, handler: nil))
            alert.present(nil)
        }
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
        
        _ = PeeringController.Notifications.peerAppeared.addObserver { notification in
            guard let again = notification.userInfo?[PeeringController.NetworkNotificationKey.again.rawValue] as? Bool else { return }
            guard let peerID = notification.userInfo?[PeeringController.NetworkNotificationKey.peerID.rawValue] as? PeerID else { return }
            guard let peer = PeeringController.shared.remote.getPeerInfo(of: peerID) else { return }

            self.peerAppeared(peer, again: again)
        }
        
        _ = PeeringController.Notifications.peerDisappeared.addObserver { notification in
            guard let peerID = notification.userInfo?[PeeringController.NetworkNotificationKey.peerID.rawValue] as? PeerID else { return }
            
            self.peerDisappeared(peerID)
        }
        
        _ = AccountController.Notifications.pinMatch.addObserver { notification in
            guard let peerID = notification.userInfo?[PeeringController.NetworkNotificationKey.peerID.rawValue] as? PeerID else { return }
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
		
		return true
	}

	func applicationWillResignActive(_ application: UIApplication) {
		// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
		// Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
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
//        RemotePeerManager.shared.clearCache()
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
            browseVC.performSegue(withIdentifier: BrowseViewController.ViewPeerSegueID, sender: peer)
            // is the new PersonDetailVC now available? I don't know... let's see, whether we can find it
            for vc in browseNavVC.viewControllers {
                guard let somePersonVC = vc as? PersonDetailViewController else { continue }
                guard somePersonVC.displayedPeerInfo == peer else { continue }
                
                somePersonVC.performSegue(withIdentifier: PersonDetailViewController.beaconSegueID, sender: nil)
            }
        }
    }
    
    static func requestPin(of peer: PeerInfo) {
        let title = NSLocalizedString("Spend Pin Points", comment: "Title of the alert which pops up when the user is about to spend in-app currency.")
        var message: String
        var actions: [UIAlertAction] = [UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)]
        
        if InAppPurchaseController.availablePinPoints >= InAppPurchaseController.PinCosts {
            message = NSLocalizedString("You have %d pin points available.", comment: "Alert message if the user is about to spend in-app currency and has enough of it in his pocket.")
            message = String(format: message, InAppPurchaseController.availablePinPoints)
            if !peer.verified {
                message = "\(message) \(NSLocalizedString("But be careful: the identitfy of the user is not verified! You may be pinning someone else!", comment: "Alert message if the user is about to pin someone who did not yet authenticate himself"))"
                actions.append(UIAlertAction(title: NSLocalizedString("Retry verify.", comment: "The user wants to retry verifying peer."), style: .default) { action in
                    PeeringController.shared.remote.verify(peer.peerID)
                })
            }
            let actionTitle = String(format: NSLocalizedString("Spend %d.", comment: "The user accepts to spend pin points for this action."), InAppPurchaseController.PinCosts)
            actions.append(UIAlertAction(title: actionTitle, style: peer.verified ? .default : .destructive) { action in
                AccountController.shared.pin(peer)
            })
        } else {
            message = NSLocalizedString("You do not have enough pin points available.", comment: "Alert message if the user is about to buy something and has not enough of in-app money in his pocket.")
            actions.append(UIAlertAction(title: NSLocalizedString("Visit Shop", comment: "Title of action which opens the shop view."), style: .default) { action in
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
    
    // MARK: Private Methods
    
    private func peerAppeared(_ peer: PeerInfo, again: Bool) {
		if !isActive {
            guard !again else { return }
            
			let note = UILocalNotification()
            let alertBodyFormat = NSLocalizedString("Found %@.", comment: "Notification alert body when a new peer was found on the network.")
			note.alertBody = String(format: alertBodyFormat, peer.nickname)
            note.userInfo = [AppDelegate.PeerIDKey : NSKeyedArchiver.archivedData(withRootObject: peer.peerID)]
			UIApplication.shared.presentLocalNotificationNow(note)
        } else if BrowseViewController.instance == nil {
            updateNewPeerBadge()
		}
	}
	
	private func peerDisappeared(_ peerID: PeerID) {
        updateNewPeerBadge()
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
    
    private func updateNewPeerBadge() {
        guard let rootTabBarController = window?.rootViewController as? UITabBarController else { return }
        
        let pm = PeeringController.shared
        let newPeerCount = pm.remote.availablePeers.filter({ pm.remote.getPeerInfo(of: $0) == nil }).count
        rootTabBarController.tabBar.items?[0].badgeValue = newPeerCount == 0 ? nil : String(newPeerCount)
    }
    
    private func setupAppearance() {
        //let theme = Theme(globalTintRed: 0/255, globalTintGreen: 128/255, globalTintBlue: 7/255, globalBackgroundRed: 177/255 /*120/255*/, globalBackgroundGreen: 1.0 /*248/255*/, globalBackgroundBlue: 184/255 /*127/255*/) //plant green
        //		let theme = Theme(globalTintRed: 0.0, globalTintGreen: 72/255, globalTintBlue: 185/255, globalBackgroundRed: 122/255, globalBackgroundGreen: 214/255, globalBackgroundBlue: 253/255) //sky blue
        //let theme = Theme(globalTintRed: 255/255, globalTintGreen: 128/255, globalTintBlue: 0/255, globalBackgroundRed: 204/255 /*213/255*/, globalBackgroundGreen: 1.0 /*250/255*/, globalBackgroundBlue: 127/255 /*128/255*/) //sugar melon
        //let theme = Theme(globalTintRed: 12/255, globalTintGreen: 96/255, globalTintBlue: 247/255, globalBackgroundRed: 121/255, globalBackgroundGreen: 251/255, globalBackgroundBlue: 214/255) //ocean green
        //        let theme = Theme(globalTint: (0/255, 72/255, 185/255), barTint: (0/255, 146/255, 0/255), globalBackground: (160/255, 255/255, 180/255)) //bright green (98/255, 255/255, 139/255)
        
        RootView.appearance().tintColor = theme.globalTintColor
        RootView.appearance().backgroundColor = theme.globalBackgroundColor
        
        UINavigationBar.appearance().tintColor = theme.barBackgroundColor
        UINavigationBar.appearance().barTintColor = theme.barTintColor
//        UINavigationBar.appearance().backgroundColor = theme.barBackgroundColor
        
        UITabBar.appearance().tintColor = theme.barTintColor
        UITabBar.appearance().backgroundColor = theme.barBackgroundColor
        
        UITableViewCell.appearance().backgroundColor = theme.globalBackgroundColor
        UITableView.appearance().separatorColor = UIColor(white: 0.3, alpha: 1.0)
        UITableView.appearance().backgroundColor = theme.globalBackgroundColor
        //        UITableView.appearance().tintColor = theme.globalTintColor
        
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
