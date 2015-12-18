//
//  BrowseViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import MultipeerConnectivity

class BrowseViewController: UITableViewController, RemotePeerManagerDelegate {
	
	private static let peerDisplayCellId = "peerDisplayCell"
	
	var filteredAvailablePeersCache: [(String, String)] = []
	
	@IBAction func unwindToBrowseViewController(segue: UIStoryboardSegue) {
		
	}
	
	override func viewDidAppear(animated: Bool) {
		filteredAvailablePeersCache = RemotePeerManager.sharedManager.filteredPeers(BrowseFilterSettings.sharedSettings)
		RemotePeerManager.sharedManager.delegate = self
	}
	
	override func viewDidDisappear(animated: Bool) {
		RemotePeerManager.sharedManager.delegate = nil
		filteredAvailablePeersCache.removeAll()
	}
	
	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return 1
	}
	
	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return filteredAvailablePeersCache.count
	}
	
	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier(BrowseViewController.peerDisplayCellId)!
		let peer = filteredAvailablePeersCache[indexPath.row]
		cell.textLabel!.text = peer.0
		cell.detailTextLabel!.text = peer.1
		return cell
	}
	
	func remotePeerAppeared(peer: MCPeerID) {
		filteredAvailablePeersCache.append((peer.displayName, RemotePeerManager.sharedManager.getPinStatus(peer)))
		// TODO extend NSTableView with indexPathOfLastRowInSection(_: Int)
		let idxPath = NSIndexPath(forRow: filteredAvailablePeersCache.count, inSection: 0)
		self.tableView.insertRowsAtIndexPaths([idxPath], withRowAnimation: .Fade)
	}
	
	func remotePeerDisappeared(peer: MCPeerID) {
		for elem in filteredAvailablePeersCache.enumerate() {
			if elem.element.0 == peer.displayName {
				filteredAvailablePeersCache.removeAtIndex(elem.index)
				self.tableView.deleteRowsAtIndexPaths([NSIndexPath(forRow: elem.index, inSection: 0)], withRowAnimation: .Fade)
				break
			}
		}
	}
}