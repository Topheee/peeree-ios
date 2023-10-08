//
//  FirstLaunchViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 24.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import PeereeCore

final class FirstLaunchViewController: UIViewController, UIPageViewControllerDelegate, UIPageViewControllerDataSource {
	private static let FirstViewControllerID = "FirstViewController"
	private static let SecondViewControllerID = "SecondViewController"
	private static let ThirdViewControllerID = "ThirdViewController"

	private var firstVC, secondVC, thirdVC: UIViewController?

	@IBAction func unwindToOnboardingViewController(_ segue: UIStoryboardSegue) { }
	
	private var pageViewController: UIPageViewController!
	
	override func viewDidLoad() {
		super.viewDidLoad()

		// Configure the page view controller and add it as a child view controller.
		pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
		pageViewController.delegate = self
		pageViewController.dataSource = self

		guard let storyboard = storyboard, let pageView = pageViewController.view else {
			assertionFailure("Could not get storyboard or page view.")
			dismiss(animated: true, completion: nil)
			return
		}

		let peerInfoVC = storyboard.instantiateViewController(withIdentifier: Self.SecondViewControllerID)

		// must contain only one vc, otherwise it crashes
		let pageViewControllers: [UIViewController]
		if PeereeIdentityViewModelController.accountExists {
			pageViewControllers = [peerInfoVC]
			firstVC = peerInfoVC
		} else {
			let explanationVC = storyboard.instantiateViewController(withIdentifier: Self.FirstViewControllerID)
			let identityVC = storyboard.instantiateViewController(withIdentifier: Self.ThirdViewControllerID)
			firstVC = explanationVC
			secondVC = peerInfoVC
			thirdVC = identityVC
			pageViewControllers = [explanationVC]
		}
		pageViewController.setViewControllers(pageViewControllers, direction: .forward, animated: false)

		self.addChild(pageViewController)
		self.view.addSubview(pageView)
		
		// Set the page view controller's bounds using an inset rect so that self's view is visible around the edges of the pages.
		var pageViewRect = self.view.bounds
		if UIDevice.current.userInterfaceIdiom == .pad {
			pageViewRect = pageViewRect.insetBy(dx: 40.0, dy: 40.0)
		}
		pageView.frame = pageViewRect

		pageViewController.didMove(toParent: self)
		
		// Add the page view controller's gesture recognizers to the root view controller's view so that the gestures are started more easily.
		self.view.gestureRecognizers = pageViewController.gestureRecognizers
	}

	// MARK: - UIPageViewControllerDelegate
	
	func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
		return UIPageViewController.SpineLocation.none
	}
	
	// MARK: - UIPageViewControllerDataSource
	
	func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
		switch viewController {
		case secondVC:
			return firstVC
		case thirdVC:
			return secondVC
		default:
			return nil
		}
	}
	
	func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
		switch viewController {
		case firstVC:
			return secondVC
		case secondVC:
			return thirdVC
		default:
			return nil
		}
	}
	
	func presentationCount(for pageViewController: UIPageViewController) -> Int {
		return PeereeIdentityViewModelController.accountExists ? 1 : 3
	}
	
	func presentationIndex(for pageViewController: UIPageViewController) -> Int {
		return 0
	}
}

