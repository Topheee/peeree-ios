//
//  ProgressManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 06.02.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation

public protocol ProgressDelegate: class {
    func progress(didUpdate progress: Progress, peerID: PeerID)
    func progress(didCancel progress: Progress, peerID: PeerID)
    func progress(didPause progress: Progress, peerID: PeerID)
    func progress(didResume progress: Progress, peerID: PeerID)
}

// IDEA parameter which incicates the minimum changed fraction needed to update the delegate, to prevent from unnecessary often queue changes 
public class ProgressManager: NSObject {
    // KVO path strings for observing changes to properties of NSProgress
    //    static let ProgressCancelledKeyPath          = "cancelled"
    private static let ProgressCompletedUnitCountKeyPath = "completedUnitCount"
    
    let peerID: PeerID
    let progress: Progress
    let targetQueue: DispatchQueue
    weak var delegate: ProgressDelegate?
    
    public init(peerID: PeerID, progress: Progress, delegate: ProgressDelegate, queue: DispatchQueue) {
        self.peerID = peerID
        self.progress = progress
        self.delegate = delegate
        targetQueue = queue
        super.init()
        //        progress.addObserver(self, forKeyPath: "cancelled", options: [.new], context: nil)
        progress.addObserver(self, forKeyPath: ProgressManager.ProgressCompletedUnitCountKeyPath, options: [], context: nil)
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
    
    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        //        super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context) this throws an exception!
        guard let progress = object as? Progress else { return }
        guard delegate != nil && keyPath != nil else { return }
        
        switch keyPath! {
            //        case "cancelled":
        //            delegate!.portraitLoadCancelled()
        case ProgressManager.ProgressCompletedUnitCountKeyPath:
            targetQueue.async {
                self.delegate?.progress(didUpdate: progress, peerID: self.peerID)
            }
        default:
            break
        }
    }
}
