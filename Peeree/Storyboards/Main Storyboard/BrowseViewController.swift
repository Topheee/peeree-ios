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
    
    private static var matchedPeersSection = 0
    private static var newPeersSection = 1
    private static var inFilterPeersSection = 2
    private static var outFilterPeersSection = 3
    
//    private var peerCache: [[MCPeerID]] = [[], [], [], []]
    private var matchedPeers: [PeerInfo] = []
    private var newPeers: [MCPeerID] = []
    private var inFilterPeers: [PeerInfo] = []
    private var outFilterPeers: [PeerInfo] = []
	
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
        guard let cellPath = tableView.indexPathForCell(tappedCell) else { return }
        
//        personDetailVC.displayedPeer = peerCache[cellPath.section][cellPath.row]
        switch cellPath.section {
        case BrowseViewController.matchedPeersSection:
            personDetailVC.displayedPeer = matchedPeers[cellPath.row].peerID
        case BrowseViewController.newPeersSection:
            personDetailVC.displayedPeer = newPeers[cellPath.row]
        case BrowseViewController.inFilterPeersSection:
            personDetailVC.displayedPeer = inFilterPeers[cellPath.row].peerID
        case BrowseViewController.outFilterPeersSection:
            personDetailVC.displayedPeer = outFilterPeers[cellPath.row].peerID
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
//		RemotePeerManager.sharedManager.delegate = self
		
        tabBarController?.tabBar.items?[0].badgeValue = nil
        UIApplication.sharedApplication().applicationIconBadgeNumber = 0
        
        NSNotificationCenter.defaultCenter().addObserverForName(RemotePeerManager.RemotePeerAppearedNotification, object: nil, queue: NSOperationQueue.mainQueue()) { (notification) in
            if let peerID = notification.userInfo?[RemotePeerManager.PeerIDKey] as? MCPeerID {
                self.remotePeerAppeared(peerID)
            }
        }
        
        NSNotificationCenter.defaultCenter().addObserverForName(RemotePeerManager.RemotePeerDisappearedNotification, object: nil, queue: NSOperationQueue.mainQueue()) { (notification) in
            if let peerID = notification.userInfo?[RemotePeerManager.PeerIDKey] as? MCPeerID {
                self.remotePeerDisappeared(peerID)
            }
        }
        
        NSNotificationCenter.defaultCenter().addObserverForName(RemotePeerManager.ConnectionChangedStateNotification, object: nil, queue: NSOperationQueue.mainQueue()) { (notification) in
            self.connectionChangedState(RemotePeerManager.sharedManager.peering)
        }
        
        NSNotificationCenter.defaultCenter().addObserverForName(RemotePeerManager.PeerInfoLoadedNotification, object: nil, queue: NSOperationQueue.mainQueue()) { (notification) in
            if let peerID = notification.userInfo?[RemotePeerManager.PeerIDKey] as? MCPeerID {
                self.peerInfoLoaded(RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID)!)
            }
        }
	}
	
	override func viewDidDisappear(animated: Bool) {
		super.viewDidDisappear(animated)
        //		RemotePeerManager.sharedManager.delegate = nil
        NSNotificationCenter.defaultCenter().removeObserver(self)
        print("detached")
        matchedPeers.removeAll()
        newPeers.removeAll()
		inFilterPeers.removeAll()
        outFilterPeers.removeAll()
        tableView.reloadData()
	}
    
    // MARK: - UITableView Data Source
	
	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return 4
	}
	
	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case BrowseViewController.matchedPeersSection:
            return matchedPeers.count
        case BrowseViewController.newPeersSection:
            return newPeers.count
        case BrowseViewController.inFilterPeersSection:
            return inFilterPeers.count
        case BrowseViewController.outFilterPeersSection:
            return outFilterPeers.count
        default:
            return 0
        }
	}
	
	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier(BrowseViewController.peerDisplayCellID)!
        
        switch indexPath.section {
        case BrowseViewController.matchedPeersSection:
            let peer = matchedPeers[indexPath.row]
            cell.textLabel!.text = peer.peerID.displayName
            cell.detailTextLabel!.text = "\(peer.gender.localizedRawValue()), \(peer.age), \(peer.relationshipStatus.localizedRawValue())"
            cell.imageView?.image = peer.picture
        case BrowseViewController.newPeersSection:
            let peerID = newPeers[indexPath.row]
            cell.textLabel!.text = peerID.displayName
            cell.detailTextLabel!.text = ""
        case BrowseViewController.inFilterPeersSection:
            let peer = inFilterPeers[indexPath.row]
            cell.textLabel!.text = peer.peerID.displayName
            cell.detailTextLabel!.text = "\(peer.gender.localizedRawValue()), \(peer.age), \(peer.relationshipStatus.localizedRawValue())"
            cell.imageView?.image = peer.picture
        case BrowseViewController.outFilterPeersSection:
            let peer = outFilterPeers[indexPath.row]
            cell.textLabel!.text = peer.peerID.displayName
            cell.detailTextLabel!.text = "\(peer.gender.localizedRawValue()), \(peer.age), \(peer.relationshipStatus.localizedRawValue())"
            cell.imageView?.image = peer.picture
        default:
            break
        }
		return cell
	}
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case BrowseViewController.matchedPeersSection:
            return NSLocalizedString("Matches", comment: "Header of table view section in browse view, which contains entries for pin matched peers.")
        case BrowseViewController.newPeersSection:
            return NSLocalizedString("New Peers", comment: "Header of table view section in browse view, which contains entries for new users around whoose data has not been loaded yet.")
        case BrowseViewController.inFilterPeersSection:
            return NSLocalizedString("People around", comment: "Header of table view section in browse view, which contains entries for peers currently available on the network (so they are nere around).")
        case BrowseViewController.outFilterPeersSection:
            return NSLocalizedString("Filtered people", comment: "Header of table view section in browse view, which contains entries for people who are most likely not interesting for the user because they did not pass his filter.")
        default:
            return super.tableView(tableView, titleForHeaderInSection: section)
        }
    }
    
    private func addPeerToView(peer: PeerInfo) -> Int {
        if peer.pinned && peer.pinnedMe {
            matchedPeers.insert(peer, atIndex: 0)
            return BrowseViewController.matchedPeersSection
        } else if BrowseFilterSettings.sharedSettings.checkPeer(peer) {
            inFilterPeers.insert(peer, atIndex: 0)
            return BrowseViewController.inFilterPeersSection
        } else {
            outFilterPeers.insert(peer, atIndex: 0)
            return BrowseViewController.outFilterPeersSection
        }
    }
    
    private func addPeerIDToView(peerID: MCPeerID, updateTable: Bool) {
        var section: Int
        if let peer = RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID) {
            section = addPeerToView(peer)
        } else {
            newPeers.insert(peerID, atIndex: 0)
            section = BrowseViewController.newPeersSection
        }
        
        if updateTable {
            addRow(0, section: section)
        }
    }
    
    private func addRow(row: Int, section: Int) {
        self.tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: row, inSection: section)], withRowAnimation: BrowseViewController.addAnimation)
        print("Added row \(row) in section \(section) in thread \(NSThread.currentThread())")
    }
    
    private func removeRow(row: Int, section: Int) {
        self.tableView.deleteRowsAtIndexPaths([NSIndexPath(forRow: row, inSection: section)], withRowAnimation: BrowseViewController.delAnimation)
        print("Remed row \(row) in section \(section) in thread \(NSThread.currentThread())")
    }
    
    // MARK: RemotePeerManagerDelegate
	
	func remotePeerAppeared(peerID: MCPeerID) {
        addPeerIDToView(peerID, updateTable: true)
	}
	
	func remotePeerDisappeared(peerID: MCPeerID) {
        if let idx = (matchedPeers.indexOf { $0.peerID == peerID }) {
            matchedPeers.removeAtIndex(idx)
            removeRow(idx, section: BrowseViewController.matchedPeersSection)
        } else if let idx = (newPeers.indexOf { $0 == peerID }) {
            newPeers.removeAtIndex(idx)
            removeRow(idx, section: BrowseViewController.newPeersSection)
        } else if let idx = (inFilterPeers.indexOf { $0.peerID == peerID }) {
            inFilterPeers.removeAtIndex(idx)
            removeRow(idx, section: BrowseViewController.inFilterPeersSection)
        } else if let idx = (outFilterPeers.indexOf { $0.peerID == peerID }) {
            outFilterPeers.removeAtIndex(idx)
            removeRow(idx, section: BrowseViewController.outFilterPeersSection)
        }
	}
    
    func connectionChangedState(nowOnline: Bool) {
        if nowOnline {
            networkButton.setTitle(NSLocalizedString("Peering", comment: "Network functionality active"), forState: .Normal)
        } else {
            networkButton.setTitle(NSLocalizedString("Offline", comment: "Network functionality inactive"), forState: .Normal)
        }
    }
    
    func peerInfoLoaded(peer: PeerInfo) {
        if let idx = (newPeers.indexOf { $0 == peer.peerID }) {
            newPeers.removeAtIndex(idx)
            let oldPath = NSIndexPath(forRow: idx, inSection: BrowseViewController.newPeersSection)
            let newPath = NSIndexPath(forRow: 0, inSection: addPeerToView(peer))
            tableView.moveRowAtIndexPath(oldPath, toIndexPath: newPath)
        }
//        remotePeerDisappeared(peer.peerID)
//        self.tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: 0, inSection: addPeerToView(peer))], withRowAnimation: BrowseViewController.addAnimation)
    }
}