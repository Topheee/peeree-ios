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
	
	static var sharedDelegate: AppDelegate { return UIApplication.sharedApplication().delegate as! AppDelegate }

    /// This is somehow set by the environment...
    var window: UIWindow?
    
	var isActive: Bool = false

    /**
     *  Registers for notifications, presents onboarding on first launch and applies GUI theme
     */
	func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
		if UIApplication.instancesRespondToSelector(#selector(UIApplication.registerUserNotificationSettings(_:))) {
			//only ask on iOS 8 or later
            UIApplication.sharedApplication().registerUserNotificationSettings(UIUserNotificationSettings(forTypes: [.Alert, .Badge, .Sound], categories: nil))
		}
        
        NSUserDefaults.standardUserDefaults().registerDefaults([WalletController.PinPointPrefKey : WalletController.initialPinPoints])
		
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
//        UITableView.appearance().tintColor = theme.globalTintColor
		
		UITableViewCell.appearance().backgroundColor = UIColor(white: 0.0, alpha: 0.0)
		UITextView.appearance().backgroundColor = UIColor(white: 0.0, alpha: 0.0)
        
        UIToolbar.appearance().tintColor = theme.globalTintColor
        
        UIActivityIndicatorView.appearance().color = theme.globalTintColor
        UIStackView.appearance().tintColor = theme.globalTintColor
        
        UIPageControl.appearance().pageIndicatorTintColor = theme.globalTintColor.colorWithAlphaComponent(0.65)
        UIPageControl.appearance().currentPageIndicatorTintColor = theme.globalTintColor
        
        UIWindow.appearance().tintColor = theme.globalTintColor
        
        RemotePeerManager.NetworkNotification.RemotePeerAppeared.addObserver { notification in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }

            self.remotePeerAppeared(peerID)
        }
        
        RemotePeerManager.NetworkNotification.RemotePeerDisappeared.addObserver { notification in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }
            
            self.remotePeerDisappeared(peerID)
        }
        
        RemotePeerManager.NetworkNotification.PinMatch.addObserver { notification in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }
            guard let peer = RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID) else { return }
            
            self.pinMatchOccured(peer)
        }
        
        RemotePeerManager.NetworkNotification.ConnectionChangedState.addObserver { notification in
            guard let topVC = self.window?.rootViewController as? UITabBarController else { return }
            guard let browseItem = topVC.tabBar.items?.first else { return }
            
            browseItem.image = UIImage(named: RemotePeerManager.sharedManager.peering ? "RadarTemplateFilled" : "RadarTemplate")
            browseItem.selectedImage = browseItem.image
        }
        
        if NSUserDefaults.standardUserDefaults().boolForKey(AppDelegate.PrefSkipOnboarding) {
            RemotePeerManager.sharedManager.peering = true
        }
		
		return true
	}

	func applicationWillResignActive(application: UIApplication) {
		// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
		// Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
	}

	func applicationDidEnterBackground(application: UIApplication) {
		// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
		// If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
		isActive = false
	}

	func applicationWillEnterForeground(application: UIApplication) {
		// Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
	}

	func applicationDidBecomeActive(application: UIApplication) {
		// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        isActive = true
        
        if !NSUserDefaults.standardUserDefaults().boolForKey(AppDelegate.PrefSkipOnboarding) {
            // this is the first launch of the app, so we show the first launch UI
            let storyboard = UIStoryboard(name:"FirstLaunch", bundle: nil)
            
            self.window!.rootViewController?.presentViewController(storyboard.instantiateInitialViewController()!, animated: false, completion: nil)
        }
        
        UIApplication.sharedApplication().cancelAllLocalNotifications()
    }

    /**
     *  Stops networking and synchronizes preferences
     */
	func applicationWillTerminate(application: UIApplication) {
        RemotePeerManager.sharedManager.peering = false
        NSUserDefaults.standardUserDefaults().synchronize()
	}
    
    func application(application: UIApplication, didReceiveLocalNotification notification: UILocalNotification) {
        guard application.applicationState == .Inactive else { return }
        guard let peerIDData = notification.userInfo?[AppDelegate.PeerIDKey] as? NSData else { return }
        guard let peerID = NSKeyedUnarchiver.unarchiveObjectWithData(peerIDData) as? MCPeerID else { return }
        
        showPeer(peerID)
    }
    
    func applicationDidReceiveMemoryWarning(application: UIApplication) {
        // TODO figure out whether this also disconnects all open sessions
        RemotePeerManager.sharedManager.peering = false
        RemotePeerManager.sharedManager.clearCache()
        InAppPurchaseController.sharedController.clearCache()
    }
    
    func finishIntroduction() {
        NSUserDefaults.standardUserDefaults().setBool(true, forKey: AppDelegate.PrefSkipOnboarding)
        // TODO test whether this one keeps alive long enough to send us the didUpdateState and whether we need to call startAdvertising
        _ = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func showPeer(peerID: MCPeerID) {
        guard let rootTabBarController = window?.rootViewController as? UITabBarController else { return }
        guard let browseNavVC = rootTabBarController.viewControllers?[0] as? UINavigationController else { return }
        guard let browseVC = browseNavVC.viewControllers[0] as? BrowseViewController else { return }
        
        rootTabBarController.selectedIndex = 0
        browseVC.performSegueWithIdentifier(BrowseViewController.ViewPeerSegueID, sender: peerID)
    }
    
    func findPeer(peerID: MCPeerID) {
        guard let rootTabBarController = window?.rootViewController as? UITabBarController else { return }
        guard let browseNavVC = rootTabBarController.viewControllers?[0] as? UINavigationController else { return }
        guard let browseVC = browseNavVC.viewControllers[0] as? BrowseViewController else { return }
        
        rootTabBarController.selectedIndex = 0
        browseVC.performSegueWithIdentifier(BrowseViewController.ViewPeerSegueID, sender: peerID)
        let test = browseNavVC.viewControllers[0] as? PersonDetailViewController
        print(test)
    }
    
    // MARK: CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .Unknown, .Resetting:
            // just wait
            break
        case .Unsupported:
            UserPeerInfo.instance.iBeaconUUID = nil
            peripheral.stopAdvertising()
            peripheral.delegate = nil
        default:
            UserPeerInfo.instance.iBeaconUUID = NSUUID()
            peripheral.stopAdvertising()
            peripheral.delegate = nil
        }
    }
    
    // MARK: Private Methods
    
	private func remotePeerAppeared(peerID: MCPeerID) {
		if !isActive {
            guard RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID) == nil else { return }
            
			let note = UILocalNotification()
            let alertBodyFormat = NSLocalizedString("Found %@.", comment: "Notification alert body when a new peer was found on the network.")
			note.alertBody = String(format: alertBodyFormat, peerID.displayName)
            note.userInfo = [AppDelegate.PeerIDKey : NSKeyedArchiver.archivedDataWithRootObject(peerID)]
			UIApplication.sharedApplication().presentLocalNotificationNow(note)
        } else if BrowseViewController.instance == nil {
            updateNewPeerBadge()
		}
	}
	
	private func remotePeerDisappeared(peerID: MCPeerID) {
        updateNewPeerBadge()
	}
    
    private func pinMatchOccured(peer: PeerInfo) {
        if isActive {
            setPinMatchBadge()
            // TODO PinMatchVC nur zeigen, wenn man nicht in der BrowseView, der PersonView des Peers oder einer FindView ist
            let pinMatchVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewControllerWithIdentifier(PinMatchViewController.StoryboardID) as! PinMatchViewController
            pinMatchVC.displayedPeer = peer
            window?.rootViewController?.presentViewController(pinMatchVC, animated: true, completion: nil)
        } else {
            let note = UILocalNotification()
            let alertBodyFormat = NSLocalizedString("Pin match with %@!", comment: "Notification alert body when a pin match occured.")
            note.alertBody = String(format: alertBodyFormat, peer.peerName)
            note.applicationIconBadgeNumber = UIApplication.sharedApplication().applicationIconBadgeNumber + 1
            note.userInfo = [AppDelegate.PeerIDKey : NSKeyedArchiver.archivedDataWithRootObject(peer.peerID)]
            UIApplication.sharedApplication().presentLocalNotificationNow(note)
        }
    }
    
    private func setPinMatchBadge() {
        guard let rootTabBarController = window?.rootViewController as? UITabBarController else { return }
        
        rootTabBarController.tabBar.items?[0].badgeValue = NSLocalizedString("Pin Match", comment: "The name of the event when two peers pinned each other.")
    }
    
    private func updateNewPeerBadge() {
        guard let rootTabBarController = window?.rootViewController as? UITabBarController else { return }
        
        let pm = RemotePeerManager.sharedManager
        var newPeerCount: Int!
        dispatch_sync(pm.availablePeers.accessQueue) {
            // we can access the set variable safely here since we are on the queue
            newPeerCount = pm.availablePeers.set.filter({ pm.getPeerInfo(forPeer: $0) == nil }).count
        }
        rootTabBarController.tabBar.items?[0].badgeValue = newPeerCount == 0 ? nil : String(newPeerCount)
    }
}
