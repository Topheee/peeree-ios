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
	
	var filteredAvailablePeersCache: [(MCPeerID, String, String)] = []
	
	@IBAction func unwindToBrowseViewController(segue: UIStoryboardSegue) {
		
	}
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		super.prepareForSegue(segue, sender: sender)
		if let personDetailVC = segue.destinationViewController as? PersonDetailViewController {
			if let tappedCell = sender as? UITableViewCell {
				if tappedCell.reuseIdentifier == BrowseViewController.peerDisplayCellId {
					personDetailVC.displayedPeer = filteredAvailablePeersCache[tappedCell.tag].0
				}
			}
		}
	}
	
	override func viewDidAppear(animated: Bool) {
		super.viewDidAppear(animated)
		filteredAvailablePeersCache = RemotePeerManager.sharedManager.filteredPeers(BrowseFilterSettings.sharedSettings)
		tableView.reloadData()
		RemotePeerManager.sharedManager.delegate = self
		
		tabBarController?.tabBar.items?[0].badgeValue = nil
	}
	
	override func viewDidDisappear(animated: Bool) {
		super.viewDidDisappear(animated)
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
		cell.textLabel!.text = peer.1
		cell.detailTextLabel!.text = peer.2
		cell.tag = indexPath.row
		return cell
	}
	
	func remotePeerAppeared(peer: MCPeerID) {
		
		filteredAvailablePeersCache.append(peer, peer.displayName, RemotePeerManager.sharedManager.getPinStatus(peer))
		// TODO extend NSTableView with indexPathOfLastRowInSection(_: Int)
		let idxPath = NSIndexPath(forRow: filteredAvailablePeersCache.count-1, inSection: 0)
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