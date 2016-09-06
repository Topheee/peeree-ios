//
//  RootViewController.swift
//  UITests
//
//  Created by Christopher Kobusch on 24.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class FirstLaunchViewController: UIViewController, UIPageViewControllerDelegate, UIPageViewControllerDataSource {
    private static let kFirstViewControllerID = "FirstViewController"
    private static let kSecondViewControllerID = "SecondViewController"
    
    private var firstViewController: UIViewController!
    private var secondViewController: UIViewController!
	
	@IBAction func unwindToOnboardingViewController(segue: UIStoryboardSegue) {
		
	}
	
	var pageViewController: UIPageViewController!
	
	override func viewDidLoad() {
		super.viewDidLoad()
        
        firstViewController = storyboard!.instantiateViewControllerWithIdentifier(FirstLaunchViewController.kFirstViewControllerID)
        secondViewController = storyboard!.instantiateViewControllerWithIdentifier(FirstLaunchViewController.kSecondViewControllerID)
        
		// Configure the page view controller and add it as a child view controller.
		pageViewController = UIPageViewController(transitionStyle: .Scroll, navigationOrientation: .Horizontal, options: nil)
		pageViewController.delegate = self
        pageViewController.dataSource = self
		pageViewController.setViewControllers([firstViewController], direction: .Forward, animated: false, completion: {done in })
        
        let pageView = pageViewController.view
        
		self.addChildViewController(pageViewController)
		self.view.addSubview(pageView)
		
		// Set the page view controller's bounds using an inset rect so that self's view is visible around the edges of the pages.
		var pageViewRect = self.view.bounds
		if UIDevice.currentDevice().userInterfaceIdiom == .Pad {
			pageViewRect = CGRectInset(pageViewRect, 40.0, 40.0)
		}
		pageView.frame = pageViewRect
		
		pageViewController.didMoveToParentViewController(self)
		
		// Add the page view controller's gesture recognizers to the root view controller's view so that the gestures are started more easily.
		self.view.gestureRecognizers = pageViewController.gestureRecognizers
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
	
	// MARK: - UIPageViewController delegate methods
	
	func pageViewController(pageViewController: UIPageViewController, spineLocationForInterfaceOrientation orientation: UIInterfaceOrientation) -> UIPageViewControllerSpineLocation {
		return UIPageViewControllerSpineLocation.None
	}
	
	// MARK: - Page View Controller Data Source
	
	func pageViewController(pageViewController: UIPageViewController, viewControllerBeforeViewController viewController: UIViewController) -> UIViewController? {
		var ret: UIViewController?
		switch viewController {
		case secondViewController:
			ret = firstViewController
		default:
			ret = nil
		}
		
		return ret
	}
	
	func pageViewController(pageViewController: UIPageViewController, viewControllerAfterViewController viewController: UIViewController) -> UIViewController? {
		var ret: UIViewController?
		switch viewController {
		case firstViewController:
			ret = secondViewController
		default:
			ret = nil
		}
		
		return ret
	}
	
	func presentationCountForPageViewController(pageViewController: UIPageViewController) -> Int {
		return 2
	}
	
	func presentationIndexForPageViewController(pageViewController: UIPageViewController) -> Int {
		return 0
	}

}

