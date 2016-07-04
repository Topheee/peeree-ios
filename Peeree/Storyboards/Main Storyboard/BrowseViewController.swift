//
//  BrowseViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import MultipeerConnectivity

final class BrowseViewController: UITableViewController, RemotePeerManagerDelegate {
    @IBOutlet weak var networkButton: UIButton!
	
    private static let peerDisplayCellID = "peerDisplayCell"
    private static let addAnimation = UITableViewRowAnimation.Automatic
    private static let delAnimation = UITableViewRowAnimation.Automatic
    
    private var availableMatchedPeersCache: [SerializablePeerInfo] = []
    private var availableNewPeersCache: [MCPeerID] = []
    private var filteredAvailablePeersCache: [SerializablePeerInfo] = []
    private var outFilteredAvailablePeersCache: [SerializablePeerInfo] = []
	
	@IBAction func unwindToBrowseViewController(segue: UIStoryboardSegue) {
		
	}
	
    @IBAction func toggleNetwork(sender: AnyObject) {
        RemotePeerManager.sharedManager.peering = !RemotePeerManager.sharedManager.peering
    }
    
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		super.prepareForSegue(segue, sender: sender)
		guard let personDetailVC = segue.destinationViewController as? PersonDetailViewController else { return }
        guard let tappedCell = sender as? UITableViewCell else { return }
        guard tappedCell.reuseIdentifier == BrowseViewController.peerDisplayCellID else { return }
        guard let cellSection = tableView.indexPathForCell(tappedCell)?.section else { return }
        
        switch cellSection {
        case 0:
            personDetailVC.displayedPeer = availableMatchedPeersCache[tappedCell.tag].peerID
        case 1:
            personDetailVC.displayedPeer = availableNewPeersCache[tappedCell.tag]
        case 2:
            personDetailVC.displayedPeer = filteredAvailablePeersCache[tappedCell.tag].peerID
        case 3:
            personDetailVC.displayedPeer = outFilteredAvailablePeersCache[tappedCell.tag].peerID
        default:
            break
        }
	}
	
	override func viewDidAppear(animated: Bool) {
		super.viewDidAppear(animated)
        tableView.tableFooterView = UIView(frame: CGRectZero)
        for peerID in RemotePeerManager.sharedManager.availablePeers {
            addPeerIDToView(peerID, updateTable: false)
        }
		tableView.reloadData()
        connectionChangedState(RemotePeerManager.sharedManager.peering)
		RemotePeerManager.sharedManager.delegate = self
		
        tabBarController?.tabBar.items?[0].badgeValue = nil
        UIApplication.sharedApplication().applicationIconBadgeNumber = 0
	}
	
	override func viewDidDisappear(animated: Bool) {
		super.viewDidDisappear(animated)
		RemotePeerManager.sharedManager.delegate = nil
		filteredAvailablePeersCache.removeAll()
	}
    
    // MARK: - UITableView Data Source
	
	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return 4
	}
	
	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return availableMatchedPeersCache.count
        case 1:
            return availableNewPeersCache.count
        case 2:
            return filteredAvailablePeersCache.count
        case 3:
            return outFilteredAvailablePeersCache.count
        default:
            return 0
        }
	}
	
	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier(BrowseViewController.peerDisplayCellID)!
        
        switch indexPath.section {
        case 0:
            let peer = availableMatchedPeersCache[indexPath.row]
            cell.textLabel!.text = peer.peerID.displayName
            cell.detailTextLabel!.text = "\(peer.gender.localizedRawValue()), \(peer.age), \(peer.relationshipStatus.localizedRawValue())"
            cell.imageView?.image = peer.picture
        case 1:
            let peerID = availableNewPeersCache[indexPath.row]
            cell.textLabel!.text = peerID.displayName
            cell.detailTextLabel!.text = ""
        case 2:
            let peer = filteredAvailablePeersCache[indexPath.row]
            cell.textLabel!.text = peer.peerID.displayName
            cell.detailTextLabel!.text = "\(peer.gender.localizedRawValue()), \(peer.age), \(peer.relationshipStatus.localizedRawValue())"
            cell.imageView?.image = peer.picture
        case 3:
            let peer = outFilteredAvailablePeersCache[indexPath.row]
            cell.textLabel!.text = peer.peerID.displayName
            cell.detailTextLabel!.text = "\(peer.gender.localizedRawValue()), \(peer.age), \(peer.relationshipStatus.localizedRawValue())"
            cell.imageView?.image = peer.picture
        default:
            break
        }
		cell.tag = indexPath.row
		return cell
	}
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return NSLocalizedString("Matches", comment: "Header of table view section in browse view, which contains entries for pin matched peers.")
        case 1:
            return NSLocalizedString("New Peers", comment: "Header of table view section in browse view, which contains entries for new users around whoose data has not been loaded yet.")
        case 2:
            return NSLocalizedString("People around", comment: "Header of table view section in browse view, which contains entries for peers currently available on the network (so they are nere around).")
        case 3:
            return NSLocalizedString("Filtered people", comment: "Header of table view section in browse view, which contains entries for people who are most likely not interesting for the user because they did not pass his filter.")
        default:
            return super.tableView(tableView, titleForHeaderInSection: section)
        }
    }
    
    private func addPeerToView(peer: SerializablePeerInfo) -> Int {
        if peer.pinned && peer.pinnedMe {
            availableMatchedPeersCache.insert(peer, atIndex: 0)
            return 0
        } else if BrowseFilterSettings.sharedSettings.checkPeer(peer) {
            filteredAvailablePeersCache.insert(peer, atIndex: 0)
            return 2
        } else {
            outFilteredAvailablePeersCache.insert(peer, atIndex: 0)
            return 3
        }
    }
    
    private func addPeerIDToView(peerID: MCPeerID, updateTable: Bool) {
        var section: Int
        if let peer = RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID) {
            section = addPeerToView(peer)
        } else {
            availableNewPeersCache.insert(peerID, atIndex: 0)
            section = 1
        }
        
        if updateTable {
            self.tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: 0, inSection: section)], withRowAnimation: BrowseViewController.addAnimation)
        }
    }
    
    // MARK: RemotePeerManagerDelegate
	
	func remotePeerAppeared(peerID: MCPeerID) {
        addPeerIDToView(peerID, updateTable: true)
	}
	
	func remotePeerDisappeared(peerID: MCPeerID) {
        if let idx = (availableMatchedPeersCache.indexOf { $0.peerID == peerID }) {
            availableMatchedPeersCache.removeAtIndex(idx)
            self.tableView.deleteRowsAtIndexPaths([NSIndexPath(forRow: idx, inSection: 0)], withRowAnimation: BrowseViewController.delAnimation)
        } else if let idx = (availableNewPeersCache.indexOf { $0 == peerID }) {
            availableNewPeersCache.removeAtIndex(idx)
            self.tableView.deleteRowsAtIndexPaths([NSIndexPath(forRow: idx, inSection: 1)], withRowAnimation: BrowseViewController.delAnimation)
        } else if let idx = (filteredAvailablePeersCache.indexOf { $0.peerID == peerID }) {
            filteredAvailablePeersCache.removeAtIndex(idx)
            self.tableView.deleteRowsAtIndexPaths([NSIndexPath(forRow: idx, inSection: 2)], withRowAnimation: BrowseViewController.delAnimation)
        } else if let idx = (outFilteredAvailablePeersCache.indexOf { $0.peerID == peerID }) {
            outFilteredAvailablePeersCache.removeAtIndex(idx)
            self.tableView.deleteRowsAtIndexPaths([NSIndexPath(forRow: idx, inSection: 3)], withRowAnimation: BrowseViewController.delAnimation)
        }
	}
    
    func connectionChangedState(nowOnline: Bool) {
        if nowOnline {
            networkButton.setTitle(NSLocalizedString("Peering", comment: "Network functionality active"), forState: .Normal)
        } else {
            networkButton.setTitle(NSLocalizedString("Offline", comment: "Network functionality inactive"), forState: .Normal)
        }
    }
    
    func peerInfoLoaded(peer: SerializablePeerInfo) {
        remotePeerDisappeared(peer.peerID)
        self.tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: 0, inSection: addPeerToView(peer))], withRowAnimation: BrowseViewController.addAnimation)
    }
}