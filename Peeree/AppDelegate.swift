//
//  AppDelegate.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import MultipeerConnectivity
import CoreBluetooth

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
        self.barBackgroundColor = UIColor(red: barBackground.r, green: barBackground.g, blue: barBackground.b, alpha: 0.3)
        barTintColor = UIColor(red: barTint.r, green: barTint.g, blue: barTint.b, alpha: 1.0)
    }
}

let theme = Theme(globalTint: (0/255, 146/255, 0/255), barTint: (0/255, 146/255, 0/255), globalBackground: (255/255, 255/255, 255/255), barBackground: (98/255, 255/255, 139/255)) //white with green

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, CBPeripheralManagerDelegate {
    static private let PrefSkipOnboarding = "peeree-prefs-skip-onboarding"
    static let PeerIDKey = "PeerIDKey"
	
	static var shared: AppDelegate { return UIApplication.shared.delegate as! AppDelegate }

    /// This is somehow set by the environment...
    var window: UIWindow?
    
	var isActive: Bool = false

    /**
     *  Registers for notifications, presents onboarding on first launch and applies GUI theme
     */
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
		if UIApplication.instancesRespond(to: #selector(UIApplication.registerUserNotificationSettings(_:))) {
			//only ask on iOS 8 or later
            UIApplication.shared.registerUserNotificationSettings(UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil))
		}
        
        UserDefaults.standard.register(defaults: [WalletController.PinPointPrefKey : WalletController.InitialPinPoints])
		
		//let theme = Theme(globalTintRed: 0/255, globalTintGreen: 128/255, globalTintBlue: 7/255, globalBackgroundRed: 177/255 /*120/255*/, globalBackgroundGreen: 1.0 /*248/255*/, globalBackgroundBlue: 184/255 /*127/255*/) //plant green
//		let theme = Theme(globalTintRed: 0.0, globalTintGreen: 72/255, globalTintBlue: 185/255, globalBackgroundRed: 122/255, globalBackgroundGreen: 214/255, globalBackgroundBlue: 253/255) //sky blue
		//let theme = Theme(globalTintRed: 255/255, globalTintGreen: 128/255, globalTintBlue: 0/255, globalBackgroundRed: 204/255 /*213/255*/, globalBackgroundGreen: 1.0 /*250/255*/, globalBackgroundBlue: 127/255 /*128/255*/) //sugar melon
        //let theme = Theme(globalTintRed: 12/255, globalTintGreen: 96/255, globalTintBlue: 247/255, globalBackgroundRed: 121/255, globalBackgroundGreen: 251/255, globalBackgroundBlue: 214/255) //ocean green
//        let theme = Theme(globalTint: (0/255, 72/255, 185/255), barTint: (0/255, 146/255, 0/255), globalBackground: (160/255, 255/255, 180/255)) //bright green (98/255, 255/255, 139/255)
        
		RootView.appearance().tintColor = theme.globalTintColor
		RootView.appearance().backgroundColor = theme.globalBackgroundColor
		
//        UINavigationBar.appearance().tintColor = theme.barTintColor
        UINavigationBar.appearance().backgroundColor = theme.barBackgroundColor
		
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
        
        _ = RemotePeerManager.NetworkNotification.peerAppeared.addObserver { notification in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.peerID.rawValue] as? MCPeerID else { return }

            self.peerAppeared(peerID)
        }
        
        _ = RemotePeerManager.NetworkNotification.peerDisappeared.addObserver { notification in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.peerID.rawValue] as? MCPeerID else { return }
            
            self.peerDisappeared(peerID)
        }
        
        _ = RemotePeerManager.NetworkNotification.pinMatch.addObserver { notification in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.peerID.rawValue] as? MCPeerID else { return }
            guard let peer = RemotePeerManager.shared.getPeerInfo(of: peerID) else { return }
            
            self.pinMatchOccured(peer)
        }
        
        _ = RemotePeerManager.NetworkNotification.connectionChangedState.addObserver { notification in
            guard let topVC = self.window?.rootViewController as? UITabBarController else { return }
            guard let browseItem = topVC.tabBar.items?.first else { return }
            
            browseItem.image = UIImage(named: RemotePeerManager.shared.peering ? "RadarTemplateFilled" : "RadarTemplate")
            browseItem.selectedImage = browseItem.image
        }
        
        if UserDefaults.standard.bool(forKey: AppDelegate.PrefSkipOnboarding) {
            RemotePeerManager.shared.peering = true
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
            
            self.window!.rootViewController?.present(storyboard.instantiateInitialViewController()!, animated: false, completion: nil)
        }
        
        UIApplication.shared.cancelAllLocalNotifications()
    }

    /**
     *  Stops networking and synchronizes preferences
     */
	func applicationWillTerminate(_ application: UIApplication) {
        RemotePeerManager.shared.peering = false
        UserDefaults.standard.synchronize()
	}
    
    func application(_ application: UIApplication, didReceive notification: UILocalNotification) {
        guard application.applicationState == .inactive else { return }
        guard let peerIDData = notification.userInfo?[AppDelegate.PeerIDKey] as? Data else { return }
        guard let peerID = NSKeyedUnarchiver.unarchiveObject(with: peerIDData) as? MCPeerID else { return }
        
        show(peer: peerID)
    }
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        // TODO figure out whether this also disconnects all open sessions
        RemotePeerManager.shared.peering = false
        RemotePeerManager.shared.clearCache()
        InAppPurchaseController.shared.clearCache()
    }
    
    func finishIntroduction() {
        UserDefaults.standard.set(true, forKey: AppDelegate.PrefSkipOnboarding)
        // TODO test whether this one keeps alive long enough to send us the didUpdateState and whether we need to call startAdvertising
        _ = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func show(peer peerID: MCPeerID) {
        guard let rootTabBarController = window?.rootViewController as? UITabBarController else { return }
        guard let browseNavVC = rootTabBarController.viewControllers?[0] as? UINavigationController else { return }
        
        rootTabBarController.selectedIndex = 0
        var browseVC: BrowseViewController? = nil
        for vc in browseNavVC.viewControllers {
            if vc is BrowseViewController {
                browseVC = vc as? BrowseViewController
            } else if let personVC = vc as? PersonDetailViewController {
                guard personVC.displayedPeerID != peerID else { return }
            }
        }
        browseVC?.performSegue(withIdentifier: BrowseViewController.ViewPeerSegueID, sender: peerID)
    }
    
    func find(peer peerID: MCPeerID) {
        guard let rootTabBarController = window?.rootViewController as? UITabBarController else { return }
        guard let browseNavVC = rootTabBarController.viewControllers?[0] as? UINavigationController else { return }
        
        rootTabBarController.selectedIndex = 0
        
        var _browseVC: BrowseViewController? = nil
        var _personVC: PersonDetailViewController? = nil
        for vc in browseNavVC.viewControllers {
            if vc is BrowseViewController {
                _browseVC = vc as? BrowseViewController
            } else if let somePersonVC = vc as? PersonDetailViewController {
                if somePersonVC.displayedPeerID == peerID {
                    _personVC = somePersonVC
                }
            } else if let someBeaconVC = vc as? BeaconViewController {
                guard someBeaconVC.searchedPeer?.peerID != peerID else { return }
            }
        }
        
        if let personVC = _personVC {
            personVC.performSegue(withIdentifier: PersonDetailViewController.beaconSegueID, sender: nil)
        } else if let browseVC = _browseVC {
            browseVC.performSegue(withIdentifier: BrowseViewController.ViewPeerSegueID, sender: peerID)
            // is the new PersonDetailVC now available? I don't know... let's see, whether we can find it
            for vc in browseNavVC.viewControllers {
                guard let somePersonVC = vc as? PersonDetailViewController else { continue }
                guard somePersonVC.displayedPeerID == peerID else { continue }
                
                somePersonVC.performSegue(withIdentifier: PersonDetailViewController.beaconSegueID, sender: nil)
            }
        }
    }
    
    // MARK: CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .unknown, .resetting:
            // just wait
            break
        case .unsupported:
            UserPeerInfo.instance.iBeaconUUID = nil
            peripheral.stopAdvertising()
            peripheral.delegate = nil
        default:
            UserPeerInfo.instance.iBeaconUUID = UUID()
            peripheral.stopAdvertising()
            peripheral.delegate = nil
        }
    }
    
    // MARK: Private Methods
    
	private func peerAppeared(_ peerID: MCPeerID) {
		if !isActive {
            guard RemotePeerManager.shared.getPeerInfo(of: peerID) == nil else { return }
            
			let note = UILocalNotification()
            let alertBodyFormat = NSLocalizedString("Found %@.", comment: "Notification alert body when a new peer was found on the network.")
			note.alertBody = String(format: alertBodyFormat, peerID.displayName)
            note.userInfo = [AppDelegate.PeerIDKey : NSKeyedArchiver.archivedData(withRootObject: peerID)]
			UIApplication.shared.presentLocalNotificationNow(note)
        } else if BrowseViewController.instance == nil {
            updateNewPeerBadge()
		}
	}
	
	private func peerDisappeared(_ peerID: MCPeerID) {
        updateNewPeerBadge()
	}
    
    private func pinMatchOccured(_ peer: PeerInfo) {
        if isActive {
            setPinMatchBadge()
            // TODO PinMatchVC nur zeigen, wenn man nicht in der BrowseView, der PersonView des Peers oder einer FindView ist
            let pinMatchVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: PinMatchViewController.StoryboardID) as! PinMatchViewController
            pinMatchVC.displayedPeer = peer
            window?.rootViewController?.present(pinMatchVC, animated: true, completion: nil)
        } else {
            let note = UILocalNotification()
            let alertBodyFormat = NSLocalizedString("Pin match with %@!", comment: "Notification alert body when a pin match occured.")
            note.alertBody = String(format: alertBodyFormat, peer.peerName)
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
        
        let pm = RemotePeerManager.shared
        var newPeerCount: Int!
        pm.availablePeers.accessQueue.sync {
            // we can access the set variable safely here since we are on the queue
            newPeerCount = pm.availablePeers.set.filter({ pm.getPeerInfo(of: $0) == nil }).count
        }
        rootTabBarController.tabBar.items?[0].badgeValue = newPeerCount == 0 ? nil : String(newPeerCount)
    }
}
