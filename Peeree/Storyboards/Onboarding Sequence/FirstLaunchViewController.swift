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
	
	@IBAction func unwindToOnboardingViewController(_ segue: UIStoryboardSegue) {
		
	}
	
	var pageViewController: UIPageViewController!
	
	override func viewDidLoad() {
		super.viewDidLoad()
        
        firstViewController = storyboard!.instantiateViewController(withIdentifier: FirstLaunchViewController.kFirstViewControllerID)
        secondViewController = storyboard!.instantiateViewController(withIdentifier: FirstLaunchViewController.kSecondViewControllerID)
        
		// Configure the page view controller and add it as a child view controller.
		pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
		pageViewController.delegate = self
        pageViewController.dataSource = self
		pageViewController.setViewControllers([firstViewController], direction: .forward, animated: false, completion: {done in })
        
        let pageView = pageViewController.view
        
		self.addChildViewController(pageViewController)
		self.view.addSubview(pageView!)
		
		// Set the page view controller's bounds using an inset rect so that self's view is visible around the edges of the pages.
		var pageViewRect = self.view.bounds
		if UIDevice.current.userInterfaceIdiom == .pad {
			pageViewRect = pageViewRect.insetBy(dx: 40.0, dy: 40.0)
		}
		pageView?.frame = pageViewRect
		
		pageViewController.didMove(toParentViewController: self)
		
		// Add the page view controller's gesture recognizers to the root view controller's view so that the gestures are started more easily.
		self.view.gestureRecognizers = pageViewController.gestureRecognizers
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
	
	// MARK: - UIPageViewController delegate methods
	
	func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewControllerSpineLocation {
		return UIPageViewControllerSpineLocation.none
	}
	
	// MARK: - Page View Controller Data Source
	
	func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
		var ret: UIViewController?
		switch viewController {
		case secondViewController:
			ret = firstViewController
		default:
			ret = nil
		}
		
		return ret
	}
	
	func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
		var ret: UIViewController?
		switch viewController {
		case firstViewController:
			ret = secondViewController
		default:
			ret = nil
		}
		
		return ret
	}
	
	func presentationCount(for pageViewController: UIPageViewController) -> Int {
		return 2
	}
	
	func presentationIndex(for pageViewController: UIPageViewController) -> Int {
		return 0
	}

}

