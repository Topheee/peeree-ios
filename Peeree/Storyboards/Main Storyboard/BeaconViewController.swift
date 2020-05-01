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

final class BeaconViewController: UIViewController {
	static let storyboardID = "BeaconViewController"

	@IBOutlet private weak var remotePortrait: UIImageView!
	@IBOutlet private weak var portraitDistanceConstraint: NSLayoutConstraint!
	@IBOutlet private weak var userPortrait: UIImageView!
	
	private var notificationObservers: [NSObjectProtocol] = []
	
	private var currentDistance = PeerDistance.unknown
	
	var peerManager: PeerManager?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		let waveColor: CGColor = AppTheme.tintColor.cgColor
		let valleyColor = AppTheme.backgroundColor.cgColor
		
		let gradient = CAGradientLayer()
		gradient.frame = view.frame
		gradient.bounds = view.bounds
		gradient.type = CAGradientLayerType.radial
		gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
		gradient.endPoint = CGPoint(x: 1 + 1/CGFloat.pi, y: -1/CGFloat.pi)
		
		gradient.colors = [waveColor, valleyColor, waveColor]
		gradient.locations = [NSNumber(floatLiteral: 0.0), NSNumber(floatLiteral: 0.5), NSNumber(floatLiteral: 1.0)]
		
		if !UIAccessibility.isReduceMotionEnabled {
			let locationAnimation = CABasicAnimation(keyPath: "locations")
			locationAnimation.fromValue = [NSNumber(floatLiteral: 0.0), NSNumber(floatLiteral: 0.1), NSNumber(floatLiteral: 0.7)]
			locationAnimation.toValue = [NSNumber(floatLiteral: 0.0), NSNumber(floatLiteral: 0.7), NSNumber(floatLiteral: 1.0)]
			locationAnimation.duration = 3.0
			locationAnimation.repeatCount = Float.greatestFiniteMagnitude
			
			let colorsAnimation = CABasicAnimation(keyPath: "colors")
			colorsAnimation.fromValue = [valleyColor, waveColor, valleyColor]
			colorsAnimation.toValue = [waveColor, valleyColor, valleyColor]
			colorsAnimation.duration = 3.0
			colorsAnimation.repeatCount = Float.greatestFiniteMagnitude
			
			gradient.add(locationAnimation, forKey: "locations")
			gradient.add(colorsAnimation, forKey: "colors")
		}
		
		view.layer.insertSublayer(gradient, at: 0)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		userPortrait.image = UserPeerManager.instance.picture ?? #imageLiteral(resourceName: "PortraitUnavailable")
		remotePortrait.image = peerManager?.picture ?? #imageLiteral(resourceName: "PortraitUnavailable")
		if #available(iOS 11.0, *) {
			userPortrait.accessibilityIgnoresInvertColors = userPortrait.image != nil
			remotePortrait.accessibilityIgnoresInvertColors = remotePortrait.image != nil
		}
		updateDistance(.unknown, animated: false)
		if let peerID = peerManager?.peerID {
			if PeeringController.shared.remote.availablePeers.contains(peerID) {
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
			notificationObservers.append(PeerManager.Notifications.pictureLoaded.addPeerObserver(for: peerID) { [weak self] _ in
				self?.remotePortrait.image = self?.peerManager?.picture ?? #imageLiteral(resourceName: "PortraitUnavailable")
			})
		}
		
		_ = CircleMaskView(maskedView: userPortrait)
		_ = CircleMaskView(maskedView: remotePortrait)
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		stopBeacon()
		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
		}
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
		
//		let titleLable = UILabel(frame: CGRect(x:0, y:0, width: 200, height: 45))
//		titleLable.text = self.searchedPeer?.nickname
//		titleLable.textColor = UIColor(white: 0.5, alpha: 1.0)
//		titleLable.textAlignment = .center
//		titleLable.lineBreakMode = .byTruncatingTail
//		self.navigationItem.titleView = titleLable
	}
	
	private func showPeerAvailable() {
		UIView.animate(withDuration: 1.0, delay: 0.0, options: .curveLinear, animations: {
			self.remotePortrait.alpha = 1.0
		}, completion: nil)
		
		startBeacon()
		
//		self.navigationItem.titleView = nil
//		self.navigationItem.title = self.searchedPeer?.nickname
	}
	
	private func startBeacon() {
		guard let manager = peerManager else { return }
		manager.range { [weak self] (_, distance) in
			DispatchQueue.main.async {
				self?.updateDistance(distance, animated: true)
			}
		}
	}
	
	private func stopBeacon() {
		peerManager?.stopRanging()
	}
}
