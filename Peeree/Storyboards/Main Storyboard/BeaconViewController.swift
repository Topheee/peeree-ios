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
    static private let OwnBeaconRegionID = "own"
    static private let PeerBeaconRegionID = "remote"

    @IBOutlet private weak var distanceView: DistanceView!
    @IBOutlet private weak var remotePortrait: UIImageView!
    @IBOutlet private weak var portraitDistanceConstraint: NSLayoutConstraint!
    @IBOutlet private weak var userPortrait: UIImageView!
    @IBOutlet private weak var portraitWidthConstraint: NSLayoutConstraint!
    
    var searchedPeer: PeerInfo?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        distanceView.controller = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        userPortrait.image = UserPeerInfo.instance.picture ?? UIImage(named: "PortraitUnavailable")
        remotePortrait.image = searchedPeer?.picture ?? UIImage(named: "PortraitUnavailable")
        updateDistance(.unknown)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startBeacon()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    // MARK: Private Methods
    
    fileprivate func updateMaskViews() {
        _ = CircleMaskView(maskedView: userPortrait)
        _ = CircleMaskView(maskedView: remotePortrait)
    }

    private func updateDistance(_ proximity: PeerDistance) {
        let multipliers: [PeerDistance : CGFloat] = [.close : 0.0, .nearby : 0.3, .far : 0.6, .unknown : 0.85]
        let multiplier = multipliers[proximity] ?? 1.0
        portraitDistanceConstraint.constant = (distanceView.frame.height - userPortrait.frame.height) * multiplier
        portraitWidthConstraint.constant = -50 * multiplier
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
    }
    
    private func showPeerAvailable() {
        UIView.animate(withDuration: 1.0, delay: 0.0, options: .curveLinear, animations: {
            self.remotePortrait.alpha = 1.0
        }, completion: nil)
    }
    
    private func startBeacon() {
        guard let peer = searchedPeer else { return }
        PeeringController.shared.range(peer.peerID) { [weak self] (_, distance) in
            DispatchQueue.main.async {
                self?.updateDistance(distance)
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
        static let StartInterval: TimeInterval = 0.75
        var index: Int = DistanceView.ringCount - 1
    }
    
    static let ringCount = 3
    
    private var timer: Timer?
    /// number of previously "installed" layers
    private var layerOffset: Int = 0
    
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
        guard let sublayers = layer.sublayers else { return }
        
        // since setting the masks in viewDidLayoutSubviews() does not work we have to inform our controller here
        controller?.updateMaskViews()
        
        var scale: CGFloat = 1.0
        var theRect = self.bounds.insetBy(dx: 2.0, dy: 2.0)
        theRect.size.height = theRect.height*2
        let position = CGPoint(x: theRect.width/2, y: theRect.height/2)
        
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
    
    func pulse(_ sender: Timer) {
        guard let pulseIndex = sender.userInfo as? PulseIndex else { sender.invalidate(); return }
        guard let previousLayer = layer.sublayers?[pulseIndex.index+layerOffset] else { sender.invalidate(); return }
        
        pulseIndex.index = pulseIndex.index > 0 ? pulseIndex.index - 1 : DistanceView.ringCount - 1
//        let timeInterval = pulseIndex.index == DistanceView.ringCount - 1 ? PulseIndex.StartInterval : 1.5*NSTimeInterval(pulseIndex.index + 1)
//        sender.fireDate = NSDate(timeInterval: timeInterval, sinceDate: sender.fireDate)
        previousLayer.shadowOpacity = 0.0
        
        let pulseLayer = layer.sublayers![pulseIndex.index+layerOffset]
        pulseLayer.shadowOpacity = 1.0
    }
    
    private func addRingLayers() {
        var scale: CGFloat = 1.0
        var theRect = self.bounds.insetBy(dx: 2.0, dy: 2.0)
        theRect.size.height = theRect.height*2
        let position = CGPoint(x: theRect.width/2, y: theRect.height/2)
        layerOffset = layer.sublayers?.count ?? 0
        
        for index in 1...DistanceView.ringCount {
            let ringLayer = CAShapeLayer()
            ringLayer.bounds = theRect
            ringLayer.position = position
            ringLayer.path = CGPath(ellipseIn: ringLayer.bounds, transform: nil)
            ringLayer.fillColor = nil
            ringLayer.strokeColor = UIColor.gray.cgColor
            ringLayer.lineWidth = 1.0 / scale
//            ringLayer.shadowPath = ringLayer.path
            ringLayer.shadowColor = self.tintColor.cgColor
            ringLayer.shadowRadius = 15.0
            self.layer.insertSublayer(ringLayer, at: UInt32(index - 1))
            scale *= 0.65
            theRect.size.width *= scale
            theRect.size.height *= scale
        }
    }
}
