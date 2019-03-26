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
    
    var searchedPeer: PeerInfo?
    
    override func viewDidLoad() {
        super.viewDidLoad()
		
		let waveColor: CGColor = AppDelegate.shared.theme.barTintColor.cgColor
		let valleyColor = UIColor.white.cgColor
		
		let gradient = CAGradientLayer()
		gradient.frame = view.frame
		gradient.bounds = view.bounds
		gradient.type = "radial" //CAGradientLayerType.radial
		gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
		gradient.endPoint = CGPoint(x: 1 + 1/CGFloat.pi, y: -1/CGFloat.pi)
		
		gradient.colors = [waveColor, valleyColor, waveColor]
		gradient.locations = [NSNumber(floatLiteral: 0.0), NSNumber(floatLiteral: 0.5), NSNumber(floatLiteral: 1.0)]
		
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
		
		view.layer.insertSublayer(gradient, at: 0)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        userPortrait.image = UserPeerInfo.instance.picture ?? #imageLiteral(resourceName: "PortraitUnavailable")
        remotePortrait.image = searchedPeer?.picture ?? #imageLiteral(resourceName: "PortraitUnavailable")
		if #available(iOS 11.0, *) {
			userPortrait.accessibilityIgnoresInvertColors = userPortrait.image != nil
			remotePortrait.accessibilityIgnoresInvertColors = remotePortrait.image != nil
		}
        updateDistance(.unknown, animated: false)
        if let peer = searchedPeer {
            if PeeringController.shared.remote.availablePeers.contains(peer.peerID) {
                showPeerAvailable()
            } else {
                showPeerUnavailable()
            }
        }
        
        notificationObservers.append(PeeringController.Notifications.peerAppeared.addObserver { (notification) in
            guard let peerID = notification.userInfo?[PeeringController.NotificationInfoKey.peerID.rawValue] as? PeerID else { return }
            guard self.searchedPeer?.peerID == peerID else { return }
            
            self.showPeerAvailable()
        })
        
        notificationObservers.append(PeeringController.Notifications.peerDisappeared.addObserver { notification in
            guard let peerID = notification.userInfo?[PeeringController.NotificationInfoKey.peerID.rawValue] as? PeerID else { return }
            guard self.searchedPeer?.peerID == peerID else { return }
            
            self.showPeerUnavailable()
        })
        
        notificationObservers.append(PeeringController.Notifications.pictureLoaded.addPeerObserver { [weak self] (peerID, _) in
            guard let strongSelf = self else { return }
            strongSelf.searchedPeer = PeeringController.shared.remote.getPeerInfo(of: peerID) ?? strongSelf.searchedPeer
            strongSelf.remotePortrait.image = strongSelf.searchedPeer?.picture ?? #imageLiteral(resourceName: "PortraitUnavailable")
        })
        
        startBeacon()
		
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
        portraitDistanceConstraint.constant = (view.frame.height - userPortrait.frame.height) * multiplier
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
        
//        let titleLable = UILabel(frame: CGRect(x:0, y:0, width: 200, height: 45))
//        titleLable.text = self.searchedPeer?.nickname
//        titleLable.textColor = UIColor(white: 0.5, alpha: 1.0)
//        titleLable.textAlignment = .center
//        titleLable.lineBreakMode = .byTruncatingTail
//        self.navigationItem.titleView = titleLable
    }
    
    private func showPeerAvailable() {
        UIView.animate(withDuration: 1.0, delay: 0.0, options: .curveLinear, animations: {
            self.remotePortrait.alpha = 1.0
        }, completion: nil)
        
//        self.navigationItem.titleView = nil
//        self.navigationItem.title = self.searchedPeer?.nickname
    }
    
    private func startBeacon() {
        guard let peer = searchedPeer else { return }
        PeeringController.shared.range(peer.peerID) { [weak self] (_, distance) in
            DispatchQueue.main.async {
                self?.updateDistance(distance, animated: true)
            }
        }
    }
    
    private func stopBeacon() {
        PeeringController.shared.stopRanging()
    }
}
