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
        return CLBeaconRegion(proximityUUID: uuid as UUID, identifier: BeaconViewController.OwnBeaconRegionID)
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
        case idle, advertising, monitoring, ranging
        case error(reason: ErrorReason, recoverable: Bool)
    }
    private var state: State = .idle {
        didSet {
            switch state {
            case .idle:
                retryButton.isEnabled = false
                errorItem.title = NSLocalizedString("Idle.", comment: "Status of the beacon view when it is not monitoring.")
            case .monitoring, .advertising:
                retryButton.isEnabled = false
                errorItem.title = NSLocalizedString("Peer unavailable.", comment: "Status of the beacon view when it is active, but the peer is not in range.")
            case .ranging:
                retryButton.isEnabled = false
                errorItem.title = nil
            case .error(let reason, let recoverable):
                removeDistanceViewAnimations()
                retryButton.isEnabled = recoverable
                errorItem.title = reason.localizedRawValue
                updateDistance(.unknown)
                showPeerUnavailable()
            }
        }
    }
    
    var searchedPeer: PeerInfo?
    
    @IBAction func retry(_ sender: AnyObject) {
        stopBeacon()
        startBeacon()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        distanceView.controller = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        userPortrait.image = UserPeerInfo.instance.picture ?? UIImage(named: "PortraitUnavailable")
        remotePortrait.image = searchedPeer?.picture ?? UIImage(named: "PortraitUnavailable")
        state = .idle
        updateDistance(.unknown)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        guard searchedPeer?.iBeaconUUID != nil else {
            state = .error(reason: .RemoteInsufficient, recoverable: false)
            return
        }
        guard ownRegion != nil else {
            handleLocationServicesUnsupportedError()
            return
        }
    
        startBeacon()
    }
    
//    override func viewDidLayoutSubviews() {
//        super.viewDidLayoutSubviews()
//    
//            _ = CircleMaskView(maskedView: userPortrait)
//            _ = CircleMaskView(maskedView: remotePortrait)
//    }
    
    // MARK: CLLocationManagerDelegate
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        removeDistanceViewAnimations()
    }
    
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        addDistanceViewAnimations()
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let beaconRegion = region as? CLBeaconRegion else { assertionFailure(); return }
        
        locationManager.stopRangingBeacons(in: beaconRegion)
        showPeerUnavailable()
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let beaconRegion = region as? CLBeaconRegion else { assertionFailure(); return }
        
        locationManager.startRangingBeacons(in: beaconRegion)
        UIView.animate(withDuration: 1.0, delay: 0.0, options: .curveLinear, animations: {
            self.remotePortrait.alpha = 1.0
        }, completion: nil)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        handleLocationError(error as NSError)
    }
    
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        return true
    }
    
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        addDistanceViewAnimations()
        state = .monitoring
    }
    
    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        guard let theError = error else { return }
        
        handleLocationError(theError as NSError)
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        stopBeacon()
        startBeacon()
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        // should be handled by the didEnter- and didExitRegion methods
    }
    
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        // CoreLocation will call this delegate method at 1 Hz with updated range information.
        updateDistance(beacons.first!.proximity)
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        handleLocationError(error as NSError)
    }
    
    func locationManager(_ manager: CLLocationManager, rangingBeaconsDidFailFor region: CLBeaconRegion, withError error: Error) {
        handleLocationError(error as NSError)
    }
    
    // MARK: CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOff:
            handleLocationError(NSError(domain: kCLErrorDomain, code: CLError.Code.rangingUnavailable.rawValue, userInfo: nil))
        case .poweredOn:
            state = .advertising
            
            let beaconPeripheralData = ownRegion.peripheralData(withMeasuredPower: nil) as NSDictionary
            assert(beaconPeripheralData as? [String : AnyObject] != nil)
            peripheral.startAdvertising(beaconPeripheralData as? [String : AnyObject])
            
        case .resetting, .unknown:
            // ignored
            break
        case .unauthorized:
            handleLocationError(NSError(domain: kCLErrorDomain, code: CLError.Code.denied.rawValue, userInfo: nil))
        case .unsupported:
            handleLocationServicesUnsupportedError()
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard error != nil else {
            handleLocationError(NSError(domain: kCLErrorDomain, code: CLError.Code.network.rawValue, userInfo: nil))
            NSLog("Bluetooth error: \(error?.localizedDescription)")
            return
        }
        guard let peerUUID = searchedPeer?.iBeaconUUID else { assertionFailure(); return }
        
        // search for peers beacon
        peerRegion = CLBeaconRegion(proximityUUID: peerUUID as UUID, identifier: BeaconViewController.PeerBeaconRegionID)
        locationManager.startMonitoring(for: peerRegion!)
    }
    
    // MARK: Private Methods
    
    fileprivate func updateMaskViews() {
        _ = CircleMaskView(maskedView: userPortrait)
        _ = CircleMaskView(maskedView: remotePortrait)
    }

    private func updateDistance(_ proximity: CLProximity) {
        let multipliers: [CLProximity : CGFloat] = [.immediate : 0.0, .near : 0.3, .far : 0.6, .unknown : 0.85]
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
    
    private func showLocationServicesUnavailableError() {
        let alertController = UIAlertController(title: NSLocalizedString("Location Services Unavailable", comment: "Title message of alerting the user that Location Services are not available."), message: NSLocalizedString("Location Services are used to find matched people. They are only active as long as you stay in \(navigationItem.title) and the app is in the foreground.", comment: "Description of 'Location Services disabled'"), preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Open Settings", comment: "Button text for opening System Settings."), style: .default, handler: {(action) in
            UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
        }))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        alertController.present(nil)
        state = .error(reason: .LocationServicesUnavailable, recoverable: true)
    }
    
    private func handleLocationServicesUnsupportedError() {
        stopBeacon()
        
        state = .error(reason: .DeviceUnsupported, recoverable: false)
    }
    
    private func handleLocationError(_ error: NSError) {
        stopBeacon()
        
        guard let clError = CLError.Code(rawValue: error.code) else { assertionFailure("Unexpected location error"); return }
        
        switch clError {
        case .locationUnknown:
            // temporary unable to gather location
            break
        case .denied:
            showLocationServicesUnavailableError()
        case .network, .rangingFailure, .regionMonitoringFailure:
            state = .error(reason: .LocationNetworkError, recoverable: true)
        case .rangingUnavailable:
            showLocationServicesUnavailableError()
        case .regionMonitoringSetupDelayed, .regionMonitoringResponseDelayed:
            state = .error(reason: .MonitoringDelayed, recoverable: true)
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
        case .denied, .restricted:
            showLocationServicesUnavailableError()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self) && CLLocationManager.isRangingAvailable() else {
                handleLocationServicesUnsupportedError()
                return
            }
            
            distanceView.pulsing = true
            // set up own beacon
            beaconManager = CBPeripheralManager(delegate: self, queue: nil)
        }
    }
    
    private func stopBeacon() {
        beaconManager?.stopAdvertising()
        beaconManager = nil
        distanceView.pulsing = false
        
        guard peerRegion != nil else { return }
        locationManager.stopRangingBeacons(in: peerRegion!)
        locationManager.stopMonitoring(for: peerRegion!)
        peerRegion = nil
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
