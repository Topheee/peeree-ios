//
//  ProgressManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 06.02.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation

public protocol ProgressManagerDelegate: AnyObject {
	func progressDidUpdate(_ progress: Progress)
	func progressDidCancel(_ progress: Progress)
	func progressDidPause(_ progress: Progress)
	func progressDidResume(_ progress: Progress)
}

// IDEA parameter which incicates the minimum changed fraction needed to update the delegate, to prevent from unnecessary often queue changes 
public class ProgressManager: NSObject {
	private static let ProgressCompletedUnitCountKeyPath = "completedUnitCount"
	
	let progress: Progress
	let targetQueue: DispatchQueue
	weak var delegate: ProgressManagerDelegate?
	
	public init(progress: Progress, delegate: ProgressManagerDelegate, queue: DispatchQueue) {
		self.progress = progress
		self.delegate = delegate
		targetQueue = queue
		super.init()
		//		progress.addObserver(self, forKeyPath: "cancelled", options: [.new], context: nil)
		progress.addObserver(self, forKeyPath: ProgressManager.ProgressCompletedUnitCountKeyPath, options: [], context: nil)
		progress.cancellationHandler = { [weak self] in
			guard let strongSelf = self else { return }
			strongSelf.targetQueue.async {
				strongSelf.delegate?.progressDidCancel(strongSelf.progress)
			}
		}
		progress.pausingHandler = { [weak self] in
			guard let strongSelf = self else { return }
			strongSelf.targetQueue.async {
				strongSelf.delegate?.progressDidPause(strongSelf.progress)
			}
		}
		progress.resumingHandler = { [weak self] in
			guard let strongSelf = self else { return }
			strongSelf.targetQueue.async {
				strongSelf.delegate?.progressDidResume(strongSelf.progress)
			}
		}
	}
	
	deinit {
		progress.removeObserver(self, forKeyPath:ProgressManager.ProgressCompletedUnitCountKeyPath)
	}
	
	override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
		//		super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context) this throws an exception!
		guard let progress = object as? Progress else { return }
		guard delegate != nil && keyPath != nil else { return }
		
		switch keyPath! {
		case ProgressManager.ProgressCompletedUnitCountKeyPath:
			targetQueue.async {
				self.delegate?.progressDidUpdate(progress)
			}
		default:
			break
		}
	}
}

extension Progress {
	enum State {
		case unstarted, processing, finished
	}
	
	var state: State {
		return completedUnitCount == 0 ? .unstarted : (completedUnitCount == totalUnitCount ? .finished : .processing)
	}
}
