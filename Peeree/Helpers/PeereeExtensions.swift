//
//  PeereeExtensions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 05.08.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

extension UIAlertController {
    /// This is the preferred method to display an UIAlertController since it sets the tint color of the global theme. 
    func present(_ completion: (() -> Void)?) {
        presentInFrontMostViewController(true, completion: completion)
        self.view.tintColor = theme.globalTintColor
    }
}

extension UIView {
    /**
     *	Animates views like they are flown in from the bottom of the screen.
     *	@param views    the views to animate
     */
    func flyInSubviews(_ views: [UIView], duration: TimeInterval, delay: TimeInterval, damping: CGFloat, velocity: CGFloat) {
        var positions = [CGRect]()
        for value in views {
            positions.append(value.frame)
            value.frame.origin.y = self.frame.height
            value.alpha = 0.0
        }
        
        UIView.animate(withDuration: duration, delay: delay, usingSpringWithDamping: damping, initialSpringVelocity: velocity, options: UIViewAnimationOptions(rawValue: 0), animations: { () -> Void in
            for (index, view) in views.enumerated() {
                view.frame = positions[index]
                view.alpha = 1.0
            }
        }, completion: nil)
    }
}

extension PeerID {
    var displayName: String {
        return PeeringController.shared.remote.getPeerInfo(of: self)?.nickname ?? NSLocalizedString("New Peer", comment: "Heading of Person View when peer information is not yet retrieved.")
    }
}

// MARK: - ProgressDelegation

protocol ProgressDelegate: class {
    func progress(didUpdate progress: Progress, peerID: PeerID)
    func progress(didCancel progress: Progress, peerID: PeerID)
    func progress(didPause progress: Progress, peerID: PeerID)
    func progress(didResume progress: Progress, peerID: PeerID)
}

class ProgressManager: NSObject {
    // KVO path strings for observing changes to properties of NSProgress
    //    static let ProgressCancelledKeyPath          = "cancelled"
    private static let ProgressCompletedUnitCountKeyPath = "completedUnitCount"
    
    let peerID: PeerID
    let progress: Progress
    let targetQueue: DispatchQueue
    weak var delegate: ProgressDelegate?
    
    init(peerID: PeerID, progress: Progress, delegate: ProgressDelegate, queue: DispatchQueue) {
        self.peerID = peerID
        self.progress = progress
        self.delegate = delegate
        targetQueue = queue
        super.init()
//        progress.addObserver(self, forKeyPath: "cancelled", options: [.new], context: nil)
        progress.addObserver(self, forKeyPath: ProgressManager.ProgressCompletedUnitCountKeyPath, options: [.new], context: nil)
        progress.cancellationHandler = { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.targetQueue.async {
                strongSelf.delegate?.progress(didCancel: strongSelf.progress, peerID: strongSelf.peerID)
            }
        }
        progress.pausingHandler = { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.targetQueue.async {
                strongSelf.delegate?.progress(didPause: strongSelf.progress, peerID: strongSelf.peerID)
            }
        }
        progress.resumingHandler = { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.targetQueue.async {
                strongSelf.delegate?.progress(didResume: strongSelf.progress, peerID: strongSelf.peerID)
            }
        }
    }
    
    deinit {
        // stop KVO
        //        progress.removeObserver(self, forKeyPath:"cancelled")
        progress.removeObserver(self, forKeyPath:ProgressManager.ProgressCompletedUnitCountKeyPath)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        //        super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context) this throws an exception!
        guard let progress = object as? Progress else { return }
        guard delegate != nil && keyPath != nil else { return }
        
        switch keyPath! {
            //        case "cancelled":
        //            delegate!.portraitLoadCancelled()
        case ProgressManager.ProgressCompletedUnitCountKeyPath:
            delegate!.progress(didUpdate: progress, peerID: peerID)
        default:
            break
        }
    }
}
