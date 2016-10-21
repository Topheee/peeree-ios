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

final class BeaconViewController: UIViewController, CLLocationManagerDelegate, CBPeripheralManagerDelegate {
    static private let OwnBeaconRegionID = "own"
    static private let PeerBeaconRegionID = "remote"

    @IBOutlet private weak var distanceView: DistanceView!
    @IBOutlet weak var remotePortrait: UIImageView!
    @IBOutlet weak var portraitDistanceConstraint: NSLayoutConstraint!
    @IBOutlet weak var userPortrait: UIImageView!
    @IBOutlet weak var portraitWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var retryButton: UIBarButtonItem!
    @IBOutlet weak var errorItem: UIBarButtonItem!
    
    private let locationManager = CLLocationManager()
    private var ownRegion: CLBeaconRegion! {
        guard let uuid = UserPeerInfo.instance.peer.iBeaconUUID else { return nil }
        return CLBeaconRegion(proximityUUID: uuid, identifier: BeaconViewController.OwnBeaconRegionID)
    }
    private var peerRegion: CLBeaconRegion?
    private var beaconManager: CBPeripheralManager?
    
    enum ErrorReason: String {
        case RemoteInsufficient, LocationServicesUnavailable, DeviceUnsupported, LocationNetworkError, MonitoringDelayed
        
        /*
         *  For genstrings
         *
         *  NSLocalizedString("DeviceInsufficient", comment: "Error: Remote peer has no iBeacon technology available.")
         *  NSLocalizedString("LocationServicesDisabled", comment: "Error: Location Services are disabled.")
         *  NSLocalizedString("DeviceUnsupported", comment: "Error: Device is lacking location features.")
         *  NSLocalizedString("LocationNetworkError", comment: "Error: Networking issues with Location Services.")
         *  NSLocalizedString("MonitoringDelayed", comment: "Error: Location Services delayed updates.")
         */
    }
    enum State {
        case Idle, Advertising, Monitoring, Ranging
        case Error(reason: ErrorReason, recoverable: Bool)
    }
    private var state: State = .Idle {
        didSet {
            switch state {
            case .Idle:
                retryButton.enabled = false
                errorItem.title = NSLocalizedString("Idle.", comment: "Status of the beacon view when it is not monitoring.")
            case .Monitoring, .Advertising:
                retryButton.enabled = false
                errorItem.title = NSLocalizedString("Peer unavailable.", comment: "Status of the beacon view when it is active, but the peer is not in range.")
            case .Ranging:
                retryButton.enabled = false
                errorItem.title = nil
            case .Error(let reason, let recoverable):
                removeDistanceViewAnimations()
                retryButton.enabled = recoverable
                errorItem.title = reason.localizedRawValue
                updateDistance(.Unknown)
                showPeerUnavailable()
            }
        }
    }
    
    var searchedPeer: PeerInfo?
    
    @IBAction func retry(sender: AnyObject) {
        stopBeacon()
        startBeacon()
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        userPortrait.image = UserPeerInfo.instance.picture
        remotePortrait.image = searchedPeer?.picture ?? UIImage(named: "PortraitUnavailable")
        state = .Idle
        updateDistance(.Unknown)
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        guard searchedPeer?.iBeaconUUID != nil else {
            state = .Error(reason: .RemoteInsufficient, recoverable: false)
            return
        }
        guard ownRegion != nil else {
            handleLocationServicesUnsupportedError()
            return
        }
    
        startBeacon()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        userPortrait.maskView = CircleMaskView(frame: userPortrait.bounds)
        remotePortrait.maskView = CircleMaskView(frame: remotePortrait.bounds)
    }
    
    // MARK: CLLocationManagerDelegate
    
    func locationManagerDidPauseLocationUpdates(manager: CLLocationManager) {
        removeDistanceViewAnimations()
    }
    
    func locationManagerDidResumeLocationUpdates(manager: CLLocationManager) {
        addDistanceViewAnimations()
    }
    
    func locationManager(manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let beaconRegion = region as? CLBeaconRegion else { assertionFailure(); return }
        
        locationManager.stopRangingBeaconsInRegion(beaconRegion)
        showPeerUnavailable()
    }
    
    func locationManager(manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let beaconRegion = region as? CLBeaconRegion else { assertionFailure(); return }
        
        locationManager.startRangingBeaconsInRegion(beaconRegion)
        UIView.animateWithDuration(1.0, delay: 0.0, options: .CurveLinear, animations: {
            self.remotePortrait.alpha = 1.0
        }, completion: nil)
    }
    
    func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        handleLocationError(error)
    }
    
    func locationManagerShouldDisplayHeadingCalibration(manager: CLLocationManager) -> Bool {
        return true
    }
    
    func locationManager(manager: CLLocationManager, didStartMonitoringForRegion region: CLRegion) {
        addDistanceViewAnimations()
        state = .Monitoring
    }
    
    func locationManager(manager: CLLocationManager, didFinishDeferredUpdatesWithError error: NSError?) {
        guard let theError = error else { return }
        
        handleLocationError(theError)
    }
    
    func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        stopBeacon()
        startBeacon()
    }
    
    func locationManager(manager: CLLocationManager, didDetermineState state: CLRegionState, forRegion region: CLRegion) {
        // should be handled by the didEnter- and didExitRegion methods
    }
    
    func locationManager(manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], inRegion region: CLBeaconRegion) {
        // CoreLocation will call this delegate method at 1 Hz with updated range information.
        updateDistance(beacons.first!.proximity)
    }
    
    func locationManager(manager: CLLocationManager, monitoringDidFailForRegion region: CLRegion?, withError error: NSError) {
        handleLocationError(error)
    }
    
    func locationManager(manager: CLLocationManager, rangingBeaconsDidFailForRegion region: CLBeaconRegion, withError error: NSError) {
        handleLocationError(error)
    }
    
    // MARK: CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .PoweredOff:
            handleLocationError(NSError(domain: kCLErrorDomain, code: CLError.RangingUnavailable.rawValue, userInfo: nil))
        case .PoweredOn:
            state = .Advertising
            
            let beaconPeripheralData = ownRegion.peripheralDataWithMeasuredPower(nil) as NSDictionary
            assert(beaconPeripheralData as? [String : AnyObject] != nil)
            peripheral.startAdvertising(beaconPeripheralData as? [String : AnyObject])
            
        case .Resetting, .Unknown:
            // ignored
            break
        case .Unauthorized:
            handleLocationError(NSError(domain: kCLErrorDomain, code: CLError.Denied.rawValue, userInfo: nil))
        case .Unsupported:
            handleLocationServicesUnsupportedError()
        }
    }
    
    func peripheralManagerDidStartAdvertising(peripheral: CBPeripheralManager, error: NSError?) {
        guard error != nil else {
            handleLocationError(NSError(domain: kCLErrorDomain, code: CLError.Network.rawValue, userInfo: nil))
            NSLog("Bluetooth error: \(error?.localizedDescription), reason: \(error?.localizedFailureReason), recovery: \(error?.localizedRecoverySuggestion)")
            return
        }
        guard let peerUUID = searchedPeer?.iBeaconUUID else { assertionFailure(); return }
        
        // search for peers beacon
        peerRegion = CLBeaconRegion(proximityUUID: peerUUID, identifier: BeaconViewController.PeerBeaconRegionID)
        locationManager.startMonitoringForRegion(peerRegion!)
    }
    
    // MARK: Private Methods

    private func updateDistance(proximity: CLProximity) {
        let multipliers: [CLProximity : CGFloat] = [.Immediate : 0.0, .Near : 0.3, .Far : 0.6, .Unknown : 0.85]
        let multiplier = multipliers[proximity] ?? 1.0
        portraitDistanceConstraint.constant = (distanceView.frame.height - userPortrait.frame.height) * multiplier
        portraitWidthConstraint.constant = -50 * multiplier
    }
    
    private func addDistanceViewAnimations() {
        UIView.animateWithDuration(1.0, delay: 0.0, options: [.Repeat, .Autoreverse], animations: {
            self.distanceView.alpha = 0.5
        }, completion: nil)
    }
    
    private func removeDistanceViewAnimations() {
        distanceView.layer.removeAllAnimations()
    }
    
    private func showPeerUnavailable() {
        UIView.animateWithDuration(1.0, delay: 0.0, options: .CurveLinear, animations: {
            self.remotePortrait.alpha = 0.5
        }, completion: nil)
    }
    
    private func showLocationServicesUnavailableError() {
        let alertController = UIAlertController(title: NSLocalizedString("Location Services Unavailable", comment: "Title message of alerting the user that Location Services are not available."), message: NSLocalizedString("Location Services are used to find matched people. They are only active as long as you stay in \(navigationItem.title) and the app is in the foreground.", comment: "Description of 'Location Services disabled'"), preferredStyle: .Alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Open Settings", comment: "Button text for opening System Settings."), style: .Default, handler: {(action) in
            UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
        }))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .Cancel, handler: nil))
        alertController.present(nil)
        state = .Error(reason: .LocationServicesUnavailable, recoverable: true)
    }
    
    private func handleLocationServicesUnsupportedError() {
        stopBeacon()
        
        state = .Error(reason: .DeviceUnsupported, recoverable: false)
    }
    
    private func handleLocationError(error: NSError) {
        stopBeacon()
        
        guard let clError = CLError(rawValue: error.code) else { assertionFailure("Unexpected location error"); return }
        
        switch clError {
        case .LocationUnknown:
            // temporary unable to gather location
            break
        case .Denied, .RegionMonitoringDenied:
            showLocationServicesUnavailableError()
        case .Network, .RangingFailure, .RegionMonitoringFailure:
            state = .Error(reason: .LocationNetworkError, recoverable: true)
        case .RangingUnavailable:
            showLocationServicesUnavailableError()
        case .RegionMonitoringSetupDelayed, .RegionMonitoringResponseDelayed:
            state = .Error(reason: .MonitoringDelayed, recoverable: true)
        default:
            assertionFailure("Unexpected location error")
        }
    }
    
    private func startBeacon() {
        guard CLLocationManager.locationServicesEnabled() else {
            showLocationServicesUnavailableError()
            return
        }
        
        switch CLLocationManager.authorizationStatus() {
        case .Denied, .Restricted:
            showLocationServicesUnavailableError()
        case .NotDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .AuthorizedAlways, .AuthorizedWhenInUse:
            guard CLLocationManager.isMonitoringAvailableForClass(CLBeaconRegion) && CLLocationManager.isRangingAvailable() else {
                handleLocationServicesUnsupportedError()
                return
            }
            
            // set up own beacon
            beaconManager = CBPeripheralManager(delegate: self, queue: nil)
        }
    }
    
    private func stopBeacon() {
        beaconManager?.stopAdvertising()
        beaconManager = nil
        
        guard peerRegion != nil else { return }
        locationManager.stopRangingBeaconsInRegion(peerRegion!)
        locationManager.stopMonitoringForRegion(peerRegion!)
        peerRegion = nil
    }
}

final class DistanceView: UIView {
    static let ringCount = 3
    
    private var timer: NSTimer?
    /// number of previously "installed" layers
    private var layerOffset: Int = 0
    
    private class PulseIndex: NSObject {
        static let StartInterval: NSTimeInterval = 0.75
        var index: Int = DistanceView.ringCount - 1
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        timer?.invalidate()
        timer = nil
        
        guard superview != nil else { return }
        
        timer = NSTimer.scheduledTimerWithTimeInterval(PulseIndex.StartInterval, target: self, selector: #selector(pulse(_:)), userInfo: PulseIndex(), repeats: true)
        timer?.tolerance = 0.09
        
        addRingLayers()
    }
    
    override func layoutSublayersOfLayer(layer: CALayer) {
        super.layoutSublayersOfLayer(layer)
        guard let sublayers = layer.sublayers else { return }
        
        var scale: CGFloat = 1.0
        var theRect = self.bounds.insetBy(dx: 2.0, dy: 2.0)
        theRect.size.height = theRect.height*2
        let position = CGPoint(x: theRect.width/2, y: theRect.height/2)
        
        for sublayer in sublayers {
            guard let ringLayer = sublayer as? CAShapeLayer else { continue }
            ringLayer.bounds = theRect
            ringLayer.position = position
            ringLayer.path = CGPathCreateWithEllipseInRect(ringLayer.bounds, nil)
//            ringLayer.shadowPath = ringLayer.path
            ringLayer.lineWidth = 1.0 / scale
            ringLayer.transform = CATransform3DMakeScale(scale, scale, 1.0)
            scale *= 0.65
        }
    }
    
    func pulse(sender: NSTimer) {
        guard let pulseIndex = sender.userInfo as? PulseIndex else { sender.invalidate(); return }
        guard let previousLayer = layer.sublayers?[pulseIndex.index+layerOffset] else { sender.invalidate(); return }
        
        pulseIndex.index = pulseIndex.index > 0 ? pulseIndex.index - 1 : DistanceView.ringCount - 1
//        let timeInterval = pulseIndex.index == DistanceView.ringCount - 1 ? PulseIndex.StartInterval : 1.5*NSTimeInterval(pulseIndex.index + 1)
//        sender.fireDate = NSDate(timeInterval: timeInterval, sinceDate: sender.fireDate)
        previousLayer.shadowOpacity = 0.0
        
        let pulseLayer = layer.sublayers![pulseIndex.index+layerOffset]
        pulseLayer.shadowOpacity = 0.5
    }
    
    private func addRingLayers() {
        var scale: CGFloat = 1.0
        var theRect = self.bounds.insetBy(dx: 2.0, dy: 2.0)
        theRect.size.height = theRect.height*2
        let position = CGPoint(x: theRect.width/2, y: theRect.height/2)
        layerOffset = layer.sublayers?.count ?? 0
        
        for _ in 1...DistanceView.ringCount {
            let ringLayer = CAShapeLayer()
            ringLayer.bounds = theRect
            ringLayer.position = position
            ringLayer.path = CGPathCreateWithEllipseInRect(ringLayer.bounds, nil)
            ringLayer.fillColor = nil
            ringLayer.strokeColor = UIColor.grayColor().CGColor
            ringLayer.lineWidth = 1.0 / scale
//            ringLayer.shadowPath = ringLayer.path
            ringLayer.shadowColor = self.tintColor.CGColor
            ringLayer.shadowRadius = 15.0
            self.layer.addSublayer(ringLayer)
            scale *= 0.65
            theRect.size.width *= scale
            theRect.size.height *= scale
        }
    }
}
