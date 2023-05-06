//
//  PeerViewControllers.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import UIKit
import PeereeCore

/// Adapter for <code>PeerObserverContainer</code>.
class PeerViewController: UIViewController, PeerObserverContainer {
	lazy var peerID: PeerID = PeerID() {
		didSet { peerObserver = PeerObserver(peerID: peerID) }
	}
	private (set) lazy var peerObserver = PeerObserver(peerID: peerID)
}

/// Adapter for <code>PeerObserverContainer</code>.
class PeerTableViewController: UITableViewController, PeerObserverContainer {
	lazy var peerID: PeerID = PeerID() {
		didSet { peerObserver = PeerObserver(peerID: peerID) }
	}
	private (set) lazy var peerObserver = PeerObserver(peerID: peerID)
}

