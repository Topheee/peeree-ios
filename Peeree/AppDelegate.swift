//
//  AppDelegate.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
	
	static internal let kPrefFirstLaunch = "peeree-prefs-first-launch"

	var window: UIWindow?

	func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
		// Override point for customization after application launch.
		let defs = NSUserDefaults.standardUserDefaults()
		if defs.objectForKey(AppDelegate.kPrefFirstLaunch) == nil {
			//this is the first launch of the app, so we show the first launch UI
			self.window = UIWindow(frame: UIScreen.mainScreen().bounds)
			
			let storyboard = UIStoryboard(name:"FirstLaunch", bundle: nil)
			
			self.window!.rootViewController = (storyboard.instantiateInitialViewController()!)
			self.window!.makeKeyAndVisible()
		}
		
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
			
			init(globalTintRed: CGFloat, globalTintGreen: CGFloat, globalTintBlue: CGFloat, globalBackgroundRed: CGFloat, globalBackgroundGreen: CGFloat, globalBackgroundBlue: CGFloat) {
				self.globalTintRed = globalTintRed
				self.globalTintGreen = globalTintGreen
				self.globalTintBlue = globalTintBlue
				self.globalTintColor = UIColor(red: self.globalTintRed, green: self.globalTintGreen, blue: self.globalTintBlue, alpha: 1.0)
				self.globalBackgroundRed = globalBackgroundRed
				self.globalBackgroundGreen = globalBackgroundGreen
				self.globalBackgroundBlue = globalBackgroundBlue
				self.globalBackgroundColor = UIColor(red: globalBackgroundRed, green: globalBackgroundGreen, blue: globalBackgroundBlue, alpha: 1.0)
				self.barBackgroundColor = UIColor(red: globalBackgroundRed*0.5, green: globalBackgroundGreen*0.5, blue: globalBackgroundBlue*0.5, alpha: 1.0)
			}
		}
		
		//let theme = Theme(globalTintRed: 0/255, globalTintGreen: 128/255, globalTintBlue: 7/255, globalBackgroundRed: 177/255 /*120/255*/, globalBackgroundGreen: 1.0 /*248/255*/, globalBackgroundBlue: 184/255 /*127/255*/) //plant green
		let theme = Theme(globalTintRed: 0.0, globalTintGreen: 72/255, globalTintBlue: 185/255, globalBackgroundRed: 122/255, globalBackgroundGreen: 214/255, globalBackgroundBlue: 253/255) //sky blue
		//let theme = Theme(globalTintRed: 255/255, globalTintGreen: 128/255, globalTintBlue: 0/255, globalBackgroundRed: 204/255 /*213/255*/, globalBackgroundGreen: 1.0 /*250/255*/, globalBackgroundBlue: 127/255 /*128/255*/) //sugar melon
		//let theme = Theme(globalTintRed: 12/255, globalTintGreen: 96/255, globalTintBlue: 247/255, globalBackgroundRed: 121/255, globalBackgroundGreen: 251/255, globalBackgroundBlue: 214/255) //ocean green
		RootView.appearance().tintColor = theme.globalTintColor
		RootView.appearance().backgroundColor = theme.globalBackgroundColor
		
		UINavigationBar.appearance().tintColor = theme.globalTintColor
		UINavigationBar.appearance().backgroundColor = theme.barBackgroundColor
		
		UITabBar.appearance().tintColor = theme.globalTintColor
		UITabBar.appearance().backgroundColor = theme.barBackgroundColor
		
		UITableView.appearance().backgroundColor = theme.globalBackgroundColor
		UITableView.appearance().separatorColor = UIColor(white: 0.3, alpha: 1.0)
		
		UITableViewCell.appearance().backgroundColor = UIColor(white: 0.0, alpha: 0.0)
		UITextView.appearance().backgroundColor = UIColor(white: 0.0, alpha: 0.0)
		
		return true
	}

	func applicationWillResignActive(application: UIApplication) {
		// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
		// Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
	}

	func applicationDidEnterBackground(application: UIApplication) {
		// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
		// If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
	}

	func applicationWillEnterForeground(application: UIApplication) {
		// Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
	}

	func applicationDidBecomeActive(application: UIApplication) {
		// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
	}

	func applicationWillTerminate(application: UIApplication) {
		// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
	}


}

