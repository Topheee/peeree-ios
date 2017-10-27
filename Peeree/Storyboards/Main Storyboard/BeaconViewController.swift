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

    @IBOutlet private weak var distanceView: DistanceView!
    @IBOutlet private weak var remotePortrait: UIImageView!
    @IBOutlet private weak var portraitDistanceConstraint: NSLayoutConstraint!
    @IBOutlet private weak var userPortrait: UIImageView!
    @IBOutlet private weak var portraitWidthConstraint: NSLayoutConstraint!
    
    private var notificationObservers: [NSObjectProtocol] = []
    
    private var currentDistance = PeerDistance.unknown
    
    var searchedPeer: PeerInfo?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        distanceView.controller = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        userPortrait.image = UserPeerInfo.instance.picture ?? #imageLiteral(resourceName: "PortraitUnavailable")
        remotePortrait.image = searchedPeer?.picture ?? #imageLiteral(resourceName: "PortraitUnavailable")
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
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopBeacon()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: Private Methods
    
    fileprivate func updateMaskViews() {
        _ = CircleMaskView(maskedView: userPortrait)
        _ = CircleMaskView(maskedView: remotePortrait)
    }
    
    private func updateDistance(_ proximity: PeerDistance, animated: Bool) {
        guard proximity != currentDistance else { return }
        
        currentDistance = proximity
        let multipliers: [PeerDistance : CGFloat] = [.close : 0.0, .nearby : 0.3, .far : 0.6, .unknown : 0.85]
        let multiplier = multipliers[proximity] ?? 1.0
        let oldFrame = remotePortrait.frame
        portraitDistanceConstraint.constant = (distanceView.frame.height - userPortrait.frame.height) * multiplier
//        portraitWidthConstraint.constant = -50 * multiplier not working and not necessary
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
    
    private func addDistanceViewAnimations() {
        UIView.animate(withDuration: 1.0, delay: 0.0, options: [.repeat, .autoreverse], animations: {
            self.distanceView.alpha = 0.5
        }, completion: nil)
    }
    
    private func removeDistanceViewAnimations() {
        distanceView.layer.removeAllAnimations()
    }
    
    private func showPeerUnavailable() {
        UIView.animate(withDuration: 1.0, delay: 0.0, options: .curveLinear, animations: {
            self.remotePortrait.alpha = 0.5
        }, completion: nil)
        
        let titleLable = UILabel(frame: CGRect(x:0, y:0, width: 200, height: 45))
        titleLable.text = self.searchedPeer?.nickname
        titleLable.textColor = UIColor(white: 0.5, alpha: 1.0)
        titleLable.textAlignment = .center
        titleLable.lineBreakMode = .byTruncatingTail
        self.navigationItem.titleView = titleLable
    }
    
    private func showPeerAvailable() {
        UIView.animate(withDuration: 1.0, delay: 0.0, options: .curveLinear, animations: {
            self.remotePortrait.alpha = 1.0
        }, completion: nil)
        
        self.navigationItem.titleView = nil
        self.navigationItem.title = self.searchedPeer?.nickname
    }
    
    private func startBeacon() {
        guard let peer = searchedPeer else { return }
        PeeringController.shared.range(peer.peerID) { [weak self] (_, distance) in
            DispatchQueue.main.async {
                self?.updateDistance(distance, animated: true)
            }
        }
        distanceView.pulsing = true
    }
    
    private func stopBeacon() {
        PeeringController.shared.stopRanging()
        distanceView.pulsing = false
    }
}

final class DistanceView: UIView {
    private class PulseIndex: NSObject {
        static let StartInterval: TimeInterval = 1.5
        var index: Int = DistanceView.ringCount - 1
    }
    
    static let ringCount = 3
    
    private var timer: Timer?
    
    weak var controller: BeaconViewController?
    
    var pulsing: Bool {
        get { return timer != nil }
        set {
            guard newValue != pulsing else { return }
            
            DispatchQueue.main.async {
                // as we have to invalidate the timer on the same THREAD as we created it we have to use the main queue, since it is always associated with the main thread
                if newValue {
                    self.timer = Timer.scheduledTimer(timeInterval: PulseIndex.StartInterval, target: self, selector: #selector(self.pulse(_:)), userInfo: PulseIndex(), repeats: true)
                    self.timer!.tolerance = 0.09
                } else {
                    self.timer!.invalidate()
                    self.timer = nil
                }
            }
        }
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil else { return }
        
        addRingLayers()
    }
    
    override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        
        // since setting the masks in viewDidLayoutSubviews() does not work we have to inform our controller here
        controller?.updateMaskViews()
        
        var scale: CGFloat = 1.0
        var theRect = self.bounds.insetBy(dx: 2.0, dy: 2.0)
        theRect.size.height = theRect.height*2
        let position = CGPoint(x: theRect.width/2, y: theRect.height/2)
        
        guard let sublayers = layer.sublayers else { return }
        for sublayer in sublayers {
            guard let ringLayer = sublayer as? CAShapeLayer else { continue }
            ringLayer.bounds = theRect
            ringLayer.position = position
            ringLayer.path = CGPath(ellipseIn: ringLayer.bounds, transform: nil)
//            ringLayer.shadowPath = ringLayer.path
            ringLayer.lineWidth = 1.0 / scale
            ringLayer.transform = CATransform3DMakeScale(scale, scale, 1.0)
            scale *= 0.65
        }
    }
    
    @objc func pulse(_ sender: Timer) {
        guard let pulseIndex = sender.userInfo as? PulseIndex else { sender.invalidate(); return }
        guard let previousLayer = layer.sublayers?[pulseIndex.index] else { sender.invalidate(); return }
        
        pulseIndex.index = pulseIndex.index > 0 ? pulseIndex.index - 1 : DistanceView.ringCount - 1
//        let timeInterval = pulseIndex.index == DistanceView.ringCount - 1 ? PulseIndex.StartInterval : 1.5*NSTimeInterval(pulseIndex.index + 1)
//        sender.fireDate = NSDate(timeInterval: timeInterval, sinceDate: sender.fireDate)
        previousLayer.shadowOpacity = 0.0
        
        let pulseLayer = layer.sublayers![pulseIndex.index]
        pulseLayer.shadowOpacity = 1.0
    }
    
    private func addRingLayers() {
        var scale: CGFloat = 1.0
        var theRect = self.bounds.insetBy(dx: 2.0, dy: 2.0)
        theRect.size.height = theRect.height*2
        let position = CGPoint(x: theRect.width/2, y: theRect.height/2)
        
        for index in 0..<DistanceView.ringCount {
            let ringLayer = CAShapeLayer()
            ringLayer.bounds = theRect
            ringLayer.position = position
            ringLayer.path = CGPath(ellipseIn: ringLayer.bounds, transform: nil)
            ringLayer.fillColor = nil
            ringLayer.strokeColor = UIColor.gray.cgColor
            ringLayer.lineWidth = 1.0 / scale
//            ringLayer.shadowPath = ringLayer.path
            ringLayer.shadowColor = self.tintColor.cgColor
            ringLayer.shadowRadius = 7.0
            layer.insertSublayer(ringLayer, at: UInt32(index))
            
            scale *= 0.65
            theRect.size.width *= scale
            theRect.size.height *= scale
        }
    }
}
