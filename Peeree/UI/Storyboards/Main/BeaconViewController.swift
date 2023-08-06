//
//  BeaconViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.09.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit
import CoreBluetooth
import CoreLocation
import PeereeDiscovery

final class BeaconViewController: PeerViewController {
	static private let waveColor: CGColor = AppTheme.tintColor.cgColor
	static private let valleyColor = AppTheme.backgroundColor.cgColor
	static let storyboardID = "BeaconViewController"

	@IBOutlet private weak var beaconView: UIView!
	@IBOutlet private weak var remotePortrait: UIImageView!
	@IBOutlet private weak var portraitDistanceConstraint: NSLayoutConstraint!
	@IBOutlet private weak var userPortrait: UIImageView!
	
	private var notificationObservers: [NSObjectProtocol] = []
	private let gradient = CAGradientLayer()
	
	private var currentDistance = PeerDistance.unknown

	override func viewDidLoad() {
		super.viewDidLoad()

		gradient.frame = view.frame
		gradient.bounds = view.bounds
		gradient.type = CAGradientLayerType.radial
		gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
		gradient.endPoint = CGPoint(x: 1 + 1/CGFloat.pi, y: -1/CGFloat.pi)
		
		gradient.colors = [BeaconViewController.waveColor, BeaconViewController.valleyColor, BeaconViewController.waveColor]
		gradient.locations = [NSNumber(floatLiteral: 0.0), NSNumber(floatLiteral: 0.5), NSNumber(floatLiteral: 1.0)]

		beaconView.layer.insertSublayer(gradient, at: 0)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		UserPeer.instance.read { _, _, picture, _ in
			self.userPortrait.image = picture.map { UIImage(cgImage: $0) } ?? #imageLiteral(resourceName: "PortraitUnavailable")
		}
		remotePortrait.image = model.picture ?? #imageLiteral(resourceName: "PortraitUnavailable")
		if #available(iOS 11.0, *) {
			userPortrait.accessibilityIgnoresInvertColors = userPortrait.image != nil
			remotePortrait.accessibilityIgnoresInvertColors = remotePortrait.image != nil
		}
		updateDistance(.unknown, animated: false)
		if model.isAvailable {
			showPeerAvailable()
		} else {
			showPeerUnavailable()
		}

		notificationObservers.append(PeeringController.Notifications.peerAppeared.addPeerObserver(for: peerID) { [weak self] _ in
			self?.showPeerAvailable()
		})
		notificationObservers.append(PeeringController.Notifications.peerDisappeared.addPeerObserver(for: peerID) { [weak self] _ in
			self?.showPeerUnavailable()
		})
		notificationObservers.append(PeerViewModel.NotificationName.pictureLoaded.addPeerObserver(for: peerID) { [weak self] _ in
			self?.remotePortrait.image = self?.model.picture ?? #imageLiteral(resourceName: "PortraitUnavailable")
		})

		if !UIAccessibility.isReduceMotionEnabled {
			let locationAnimation = CABasicAnimation(keyPath: "locations")
			locationAnimation.fromValue = [NSNumber(floatLiteral: 0.0), NSNumber(floatLiteral: 0.1), NSNumber(floatLiteral: 0.7)]
			locationAnimation.toValue = [NSNumber(floatLiteral: 0.0), NSNumber(floatLiteral: 0.7), NSNumber(floatLiteral: 1.0)]
			locationAnimation.duration = 3.0
			locationAnimation.repeatCount = Float.greatestFiniteMagnitude

			let colorsAnimation = CABasicAnimation(keyPath: "colors")
			colorsAnimation.fromValue = [BeaconViewController.valleyColor, BeaconViewController.waveColor, BeaconViewController.valleyColor]
			colorsAnimation.toValue = [BeaconViewController.waveColor, BeaconViewController.valleyColor, BeaconViewController.valleyColor]
			colorsAnimation.duration = 3.0
			colorsAnimation.repeatCount = Float.greatestFiniteMagnitude

			gradient.add(locationAnimation, forKey: "locations")
			gradient.add(colorsAnimation, forKey: "colors")
		}

		tabBarController?.tabBar.isTranslucent = false
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		stopBeacon()
		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
		}

		tabBarController?.tabBar.isTranslucent = true
	}
	
	// MARK: Private Methods
	
	private func updateDistance(_ proximity: PeerDistance, animated: Bool) {
		guard proximity != currentDistance else { return }
		
		currentDistance = proximity
		let multipliers: [PeerDistance : CGFloat] = [.close : 0.0, .nearby : 0.3, .far : 0.6, .unknown : 0.85]
		let multiplier = multipliers[proximity] ?? 1.0
		let oldFrame = remotePortrait.frame
		portraitDistanceConstraint.constant = (view.frame.height - (navigationController?.navigationBar.frame.height ?? 0.0) - userPortrait.frame.height) * multiplier
		if animated {
			remotePortrait.setNeedsLayout()
			view.layoutIfNeeded()
			let newFrame = remotePortrait.frame
			remotePortrait.frame = oldFrame
			// duration has to be lower than the smallest range interval in PeeringController!
			UIView.animate(withDuration: 2.0) {
				self.remotePortrait.frame = newFrame
			}
		}
	}
	
	private func showPeerUnavailable() {
		UIView.animate(withDuration: 1.0, delay: 0.0, options: .curveLinear, animations: {
			self.remotePortrait.alpha = 0.5
		}, completion: nil)
		
		stopBeacon()
	}
	
	private func showPeerAvailable() {
		UIView.animate(withDuration: 1.0, delay: 0.0, options: .curveLinear, animations: {
			self.remotePortrait.alpha = 1.0
		}, completion: nil)
		
		startBeacon()
	}
	
	private func startBeacon() {
		PeeringController.shared.range(peerID) { [weak self] (_, distance) in
			DispatchQueue.main.async {
				self?.updateDistance(distance, animated: true)
			}
		}
	}
	
	private func stopBeacon() {
		PeeringController.shared.stopRanging()
	}
}
