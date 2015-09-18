//
//  RootViewController.swift
//  UITests
//
//  Created by Christopher Kobusch on 24.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class FirstLaunchViewController: UIPageViewController, UIPageViewControllerDelegate, UIPageViewControllerDataSource {
	
	@IBAction func unwindToOnboardingViewController(segue: UIStoryboardSegue) {
		NSLog("%@", "unwind")
	}
	
	var pageViewController: UIPageViewController?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
		// Configure the page view controller and add it as a child view controller.
		self.pageViewController = UIPageViewController(transitionStyle: .Scroll, navigationOrientation: .Horizontal, options: nil)
		self.pageViewController!.delegate = self

		self.pageViewController!.dataSource = self
		self.pageViewController!.setViewControllers([self.storyboard!.instantiateViewControllerWithIdentifier("FirstViewController")], direction: .Forward, animated: false, completion: {done in })
//		self.delegate = self
//		
//		self.dataSource = self
//		self.setViewControllers([self.storyboard!.instantiateViewControllerWithIdentifier("FirstViewController")], direction: .Forward, animated: false, completion: {done in })
		
//		let firstViewController = self.storyboard!.instantiateViewControllerWithIdentifier("FirstViewController") as! UIViewController
//		let secondViewController = self.storyboard!.instantiateViewControllerWithIdentifier("SecondViewController") as! UIViewController
//		let thirdViewController = self.storyboard!.instantiateViewControllerWithIdentifier("ThirdViewController") as! UIViewController
//		let fourthViewController = self.storyboard!.instantiateViewControllerWithIdentifier("FourthViewController") as! UIViewController
//		let viewControllers = [firstViewController, secondViewController, thirdViewController, fourthViewController]
//		self.pageViewController!.setViewControllers(viewControllers, direction: .Forward, animated: false, completion: {done in })
		
		
		
		self.addChildViewController(self.pageViewController!)
		self.view.addSubview(self.pageViewController!.view)
		
		// Set the page view controller's bounds using an inset rect so that self's view is visible around the edges of the pages.
		var pageViewRect = self.view.bounds
		if UIDevice.currentDevice().userInterfaceIdiom == .Pad {
			pageViewRect = CGRectInset(pageViewRect, 40.0, 40.0)
		}
		self.pageViewController!.view.frame = pageViewRect
		
		self.pageViewController!.didMoveToParentViewController(self)
		
		// Add the page view controller's gesture recognizers to the book view controller's view so that the gestures are started more easily.
		self.view.gestureRecognizers = self.pageViewController!.gestureRecognizers
	}
	
	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}
	
	// MARK: - UIPageViewController delegate methods
	
	func pageViewController(pageViewController: UIPageViewController, spineLocationForInterfaceOrientation orientation: UIInterfaceOrientation) -> UIPageViewControllerSpineLocation {
		return UIPageViewControllerSpineLocation.None
	}
	
	/*
	func pageViewController(pageViewController: UIPageViewController, spineLocationForInterfaceOrientation orientation: UIInterfaceOrientation) -> UIPageViewControllerSpineLocation {
		if (orientation == .Portrait) || (orientation == .PortraitUpsideDown) || (UIDevice.currentDevice().userInterfaceIdiom == .Phone) {
			// In portrait orientation or on iPhone: Set the spine position to "min" and the page view controller's view controllers array to contain just one view controller. Setting the spine position to 'UIPageViewControllerSpineLocationMid' in landscape orientation sets the doubleSided property to YES, so set it to NO here.
//			let currentViewController = self.pageViewController!.viewControllers[0] as! UIViewController
//			let viewControllers = [currentViewController]
//			self.pageViewController!.setViewControllers(viewControllers, direction: .Forward, animated: true, completion: {done in })
			
			self.pageViewController!.doubleSided = false
			return .Min
		}
		
		// In landscape orientation: Set the spine location to "mid" and the page view controller's view controllers array to contain two view controllers. If the current page is even, set it to contain the current and next view controllers; if it is odd, set the array to contain the previous and current view controllers.
//		let currentViewController = self.pageViewController!.viewControllers[0] as! UIViewController
//		var viewControllers: [AnyObject]
//		
//		let indexOfCurrentViewController = self.modelController.indexOfViewController(currentViewController)
//		if (indexOfCurrentViewController == 0) || (indexOfCurrentViewController % 2 == 0) {
//			let nextViewController = self.modelController.pageViewController(self.pageViewController!, viewControllerAfterViewController: currentViewController)
//			viewControllers = [currentViewController, nextViewController!]
//		} else {
//			let previousViewController = self.modelController.pageViewController(self.pageViewController!, viewControllerBeforeViewController: currentViewController)
//			viewControllers = [previousViewController!, currentViewController]
//		}
//		self.pageViewController!.setViewControllers(viewControllers, direction: .Forward, animated: true, completion: {done in })
		
		return .Mid
	}
*/
	
	// MARK: - Page View Controller Data Source
	
	func pageViewController(pageViewController: UIPageViewController, viewControllerBeforeViewController viewController: UIViewController) -> UIViewController? {
		var ret: UIViewController?
		switch (viewController.title!) {
		case "Second":
			ret = self.storyboard!.instantiateViewControllerWithIdentifier("FirstViewController")
		default:
			ret = nil
		}
		
		return ret
	}
	
	func pageViewController(pageViewController: UIPageViewController, viewControllerAfterViewController viewController: UIViewController) -> UIViewController? {
		var ret: UIViewController?
		switch (viewController.title!) {
		case "First":
			ret = self.storyboard!.instantiateViewControllerWithIdentifier("SecondViewController")
		default:
			ret = nil
		}
		
		return ret
	}
	
	func presentationCountForPageViewController(pageViewController: UIPageViewController) -> Int {
		return 2;
	}
	
	func presentationIndexForPageViewController(pageViewController: UIPageViewController) -> Int {
		return 0;
	}

}

