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
    @IBOutlet weak var retryButton: UIButton!
    @IBOutlet weak var errorLabel: UILabel!
    
    var searchedPeer: PeerInfo?
    
    private let locationManager = CLLocationManager()
    private var ownRegion: CLBeaconRegion! {
        guard let uuid = UserPeerInfo.instance.peer.iBeaconUUID else { return nil }
        return CLBeaconRegion(proximityUUID: uuid, identifier: BeaconViewController.OwnBeaconRegionID)
    }
    private var peerRegion: CLBeaconRegion?
    private var beaconManager: CBPeripheralManager?
    
    @IBAction func retry(sender: AnyObject) {
        stopBeacon()
        startBeacon()
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        userPortrait.image = UserPeerInfo.instance.picture
        remotePortrait.image = searchedPeer?.picture ?? UIImage(named: "PortraitUnavailable")
        showNoError()
        updateDistance(.Unknown)
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        guard searchedPeer?.iBeaconUUID != nil else {
            showError(NSLocalizedString("Remote cannot be searched.", comment: "Error description that remote peer has no iBeacon technology available."), recoverable: false)
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
        showNoError()
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
            showNoError()
            
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
        let multipliers: [CLProximity : CGFloat] = [.Immediate : 0.0, .Near : 0.3, .Far : 0.7, .Unknown : 1.0]
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
    
    private func showLocationServicesDeniedError() {
        let alertController = UIAlertController(title: NSLocalizedString("Location Services Disabled", comment: "Title message of alerting the user that Location Services are not authorized."), message: NSLocalizedString("Location Services are used to find matched people. They are only active as long as you stay in \(navigationItem.title) and the app is in the foreground.", comment: "Description of 'Location Services disabled'"), preferredStyle: .Alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Open Settings", comment: "Button text for opening System Settings."), style: .Default, handler: {(action) in
            UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
        }))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .Cancel, handler: nil))
        alertController.present(nil)
        showError(NSLocalizedString("Location Services Disabled.", comment: "Short description that location services are disabled."), recoverable: true)
    }
    
    private func showLocationServicesUnavailableError() {
        let alertController = UIAlertController(title: NSLocalizedString("Location Services Unavailable", comment: "Title message of alerting the user that Location Services are not available."), message: NSLocalizedString("Turn on bluetooth and Location Services.", comment: "Description of 'Location Services Unavailable'"), preferredStyle: .Alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Open Settings", comment: "Button text for opening System Settings."), style: .Default, handler: {(action) in
            UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
        }))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .Cancel, handler: nil))
        alertController.present(nil)
        showError(NSLocalizedString("Location Services are disabled.", comment: "Short description that location services are disabled."), recoverable: true)
    }
    
    private func handleLocationServicesUnsupportedError() {
        stopBeacon()
        
        let alertController = UIAlertController(title: NSLocalizedString("Device not supported", comment: "Title message of alerting the user that the device is incapable of needed location features."), message: NSLocalizedString("This app uses Apple iBeacon technology to measure distance. However, this technology is not available on your device.", comment: "Description of 'Device not supported'"), preferredStyle: .Alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .Cancel, handler: nil))
        alertController.present(nil)
    }
    
    private func handleLocationError(error: NSError) {
        stopBeacon()
        
        guard let clError = CLError(rawValue: error.code) else { assertionFailure("Unexpected location error"); return }
        
        switch clError {
        case .LocationUnknown:
            // temporary unable to gather location
            break
        case .Denied, .RegionMonitoringDenied:
            showLocationServicesDeniedError()
        case .Network, .RangingFailure, .RegionMonitoringFailure:
            showError(NSLocalizedString("Location network error.", comment: "Short description for networking issues with Location Services."), recoverable: true)
        case .RangingUnavailable:
            showLocationServicesUnavailableError()
        case .RegionMonitoringSetupDelayed, .RegionMonitoringResponseDelayed:
            showError(NSLocalizedString("Pending.", comment: "Short description of delay errors."), recoverable: false)
        default:
            assertionFailure("Unexpected location error")
        }
    }
    
    private func showError(message: String, recoverable: Bool) {
        removeDistanceViewAnimations()
        retryButton.hidden = !recoverable
        errorLabel.text = message
        errorLabel.hidden = false
        updateDistance(.Unknown)
        showPeerUnavailable()
    }
    
    private func showNoError() {
        retryButton.hidden = true
        errorLabel.hidden = true
    }
    
    private func startBeacon() {
        guard CLLocationManager.locationServicesEnabled() else {
            showLocationServicesUnavailableError()
            return
        }
        
        switch CLLocationManager.authorizationStatus() {
        case .Denied, .Restricted:
            showLocationServicesDeniedError()
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
    override func drawRect(rect: CGRect) {
        UIColor.darkGrayColor().setStroke()
        var theRect = rect.insetBy(dx: 2.0, dy: 2.0)
        theRect.size.height = theRect.height*2
        UIBezierPath(ovalInRect: theRect).stroke()
        
        let ringCount = 3
        let scale: CGFloat = 0.65
        for _ in 1...ringCount {
            theRect.origin.y = theRect.origin.y + theRect.height*(1.0-scale)*0.5
            theRect.origin.x = theRect.origin.x + theRect.width*(1.0-scale)*0.5
            theRect.size.height = theRect.height*scale
            theRect.size.width = theRect.width*scale
            UIBezierPath(ovalInRect: theRect).stroke()
        }
    }
}
