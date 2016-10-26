//
//  BrowseViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import MultipeerConnectivity

final class BrowseViewController: UITableViewController {
    @IBOutlet weak var networkButton: UIButton!
	
    private static let PeerDisplayCellID = "peerDisplayCell"
    private static let OfflineModeCellID = "offlineModeCell"
    private static let AddAnimation = UITableViewRowAnimation.automatic
    private static let DelAnimation = UITableViewRowAnimation.automatic
    
    private static let MatchedPeersSection = 0
    private static let NewPeersSection = 1
    private static let InFilterPeersSection = 2
    private static let OutFilterPeersSection = 3
    
    static let ViewPeerSegueID = "ViewPeerSegue"
    
//    private var peerCache: [[MCPeerID]] = [[], [], [], []]
    private var matchedPeers: [PeerInfo] = []
    private var newPeers: [MCPeerID] = []
    private var inFilterPeers: [PeerInfo] = []
    private var outFilterPeers: [PeerInfo] = []
    
    private var notificationObservers: [AnyObject] = []
    
    static var instance: BrowseViewController?
	
	@IBAction func unwindToBrowseViewController(_ segue: UIStoryboardSegue) {
		
	}
	
    @IBAction func toggleNetwork(_ sender: AnyObject) {
        RemotePeerManager.sharedManager.peering = !RemotePeerManager.sharedManager.peering
    }
    
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: sender)
		guard let personDetailVC = segue.destination as? PersonDetailViewController else { return }
        guard let tappedCell = sender as? UITableViewCell else {
            personDetailVC.displayedPeerID = sender as? MCPeerID
            return
        }
        guard tappedCell.reuseIdentifier == BrowseViewController.PeerDisplayCellID else { return }
        guard let cellPath = tableView.indexPath(for: tappedCell) else { return }
        
        switch cellPath.section {
        case BrowseViewController.MatchedPeersSection:
            personDetailVC.displayedPeerID = matchedPeers[cellPath.row].peerID
        case BrowseViewController.NewPeersSection:
            personDetailVC.displayedPeerID = newPeers[cellPath.row]
        case BrowseViewController.InFilterPeersSection:
            personDetailVC.displayedPeerID = inFilterPeers[cellPath.row].peerID
        case BrowseViewController.OutFilterPeersSection:
            personDetailVC.displayedPeerID = outFilterPeers[cellPath.row].peerID
        default:
            break
        }
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
        BrowseViewController.instance = self
        tableView.tableFooterView = UIView(frame: CGRect.zero)
        RemotePeerManager.sharedManager.availablePeers.accessQueue.sync {
            // we can access the set variable safely here since we are on the queue
            for peerID in RemotePeerManager.sharedManager.availablePeers.set {
                self.addPeerIDToView(peerID, updateTable: false)
            }
        }
        
		tableView.reloadData()
        connectionChangedState(RemotePeerManager.sharedManager.peering)
		
        tabBarController?.tabBar.items?[0].badgeValue = nil
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.RemotePeerAppeared.addObserver { (notification) in
            if let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID {
                self.remotePeerAppeared(peerID)
            }
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.RemotePeerDisappeared.addObserver { notification in
            if let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID {
                self.remotePeerDisappeared(peerID)
            }
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.ConnectionChangedState.addObserver { notification in
            self.connectionChangedState(RemotePeerManager.sharedManager.peering)
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.PeerInfoLoaded.addObserver { notification in
            if let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID {
                self.peerInfoLoaded(RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID)!)
            }
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.PictureLoaded.addObserver { (notification) in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID else { return }
            guard let peer = RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID) else { return }
            
            var index, section: Int?
            let array = [(self.inFilterPeers, BrowseViewController.InFilterPeersSection), (self.outFilterPeers, BrowseViewController.OutFilterPeersSection), (self.matchedPeers, BrowseViewController.MatchedPeersSection)]
            for a in array {
                index = a.0.index(of: peer)
                if index != nil {
                    section = a.1
                    break
                }
            }
            
            guard index != nil && section != nil else { return }
            self.tableView.reloadRows(at: [IndexPath(row: index!, section: section!)], with: .automatic)
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.PinMatch.addObserver { notification in
            if let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.PeerID.rawValue] as? MCPeerID {
                self.pinMatchOccured(RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID)!)
            }
        })
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        clearCache()
        BrowseViewController.instance = nil
	}
    
    // MARK: UITableView Data Source
	
	override func numberOfSections(in tableView: UITableView) -> Int {
        return RemotePeerManager.sharedManager.peering ? 4 : 1
	}
	
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if RemotePeerManager.sharedManager.peering {
            switch section {
            case BrowseViewController.MatchedPeersSection:
                return matchedPeers.count
            case BrowseViewController.NewPeersSection:
                return newPeers.count
            case BrowseViewController.InFilterPeersSection:
                return inFilterPeers.count
            case BrowseViewController.OutFilterPeersSection:
                return outFilterPeers.count
            default:
                return 0
            }
        } else {
            return 1
        }
	}
	
	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard RemotePeerManager.sharedManager.peering else {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: BrowseViewController.OfflineModeCellID) as? OfflineTableViewCell else {
                assertionFailure()
                return UITableViewCell()
            }
            
            cell.peersMetLabel.text = String(RemotePeerManager.sharedManager.peersMet)
            return cell
        }
        
		let cell = tableView.dequeueReusableCell(withIdentifier: BrowseViewController.PeerDisplayCellID)!
        
        switch indexPath.section {
        case BrowseViewController.MatchedPeersSection:
            let peer = matchedPeers[indexPath.row]
            cell.textLabel!.text = peer.peerID.displayName
            cell.detailTextLabel!.text = peer.summary
            addPictureToCell(cell, peer: peer)
        case BrowseViewController.NewPeersSection:
            let peerID = newPeers[indexPath.row]
            cell.textLabel!.text = peerID.displayName
            cell.detailTextLabel!.text = ""
            cell.imageView?.image = nil
        case BrowseViewController.InFilterPeersSection:
            let peer = inFilterPeers[indexPath.row]
            cell.textLabel!.text = peer.peerID.displayName
            cell.detailTextLabel!.text = peer.summary
            addPictureToCell(cell, peer: peer)
        case BrowseViewController.OutFilterPeersSection:
            let peer = outFilterPeers[indexPath.row]
            cell.textLabel!.text = peer.peerID.displayName
            cell.detailTextLabel!.text = peer.summary
            addPictureToCell(cell, peer: peer)
        default:
            break
        }
        
		return cell
	}
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard RemotePeerManager.sharedManager.peering else {
            return nil
        }
        
        switch section {
        case BrowseViewController.MatchedPeersSection:
            return matchedPeers.count > 0 ? NSLocalizedString("Matches", comment: "Header of table view section in browse view, which contains entries for pin matched peers.") : nil
        case BrowseViewController.NewPeersSection:
            return newPeers.count > 0 ? NSLocalizedString("New Peers", comment: "Header of table view section in browse view, which contains entries for new users around whoose data has not been loaded yet.") : nil
        case BrowseViewController.InFilterPeersSection:
            return inFilterPeers.count > 0 ? NSLocalizedString("People around", comment: "Header of table view section in browse view, which contains entries for peers currently available on the network (so they are nere around).") : nil
        case BrowseViewController.OutFilterPeersSection:
            return outFilterPeers.count > 0 ? NSLocalizedString("Filtered people", comment: "Header of table view section in browse view, which contains entries for people who are most likely not interesting for the user because they did not pass his filter.") : nil
        default:
            return super.tableView(tableView, titleForHeaderInSection: section)
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return RemotePeerManager.sharedManager.peering ? super.tableView(tableView, heightForRowAt: indexPath) : tableView.frame.height - (self.tabBarController?.tabBar.frame.height ?? 49) - (self.navigationController?.navigationBar.frame.height ?? 44) - UIApplication.shared.statusBarFrame.height
    }
    
    // MARK: Private Methods
    
    func addPictureToCell(_ cell: UITableViewCell, peer: PeerInfo) {
        guard let imageView = cell.imageView else { return }
        imageView.image = peer.picture
        guard let originalImageSize = imageView.image?.size else { return }
        
        let minImageEdgeLength = min(originalImageSize.height, originalImageSize.width)
        guard let croppedImage = imageView.image?.croppedImage(CGRect(x: (originalImageSize.width - minImageEdgeLength) / 2, y: (originalImageSize.height - minImageEdgeLength) / 2, width: minImageEdgeLength, height: minImageEdgeLength)) else { return }
        
        UIGraphicsBeginImageContextWithOptions(CGSize(squareEdgeLength: cell.contentView.marginFrame.height), true, UIScreen.main.scale)
        let imageRect = CGRect(squareEdgeLength: cell.contentView.marginFrame.height)
        croppedImage.draw(in: imageRect)
        imageView.image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        _ = CircleMaskView(maskedView: imageView)
    }
    
    private func addPeerToView(_ peer: PeerInfo) -> Int {
        if peer.pinMatched {
            matchedPeers.insert(peer, at: 0)
            return BrowseViewController.MatchedPeersSection
        } else if BrowseFilterSettings.sharedSettings.checkPeer(peer) {
            inFilterPeers.insert(peer, at: 0)
            return BrowseViewController.InFilterPeersSection
        } else {
            outFilterPeers.insert(peer, at: 0)
            return BrowseViewController.OutFilterPeersSection
        }
    }
    
    private func addPeerIDToView(_ peerID: MCPeerID, updateTable: Bool) {
        var section: Int
        if let peer = RemotePeerManager.sharedManager.getPeerInfo(forPeer: peerID) {
            section = addPeerToView(peer)
        } else {
            newPeers.insert(peerID, at: 0)
            section = BrowseViewController.NewPeersSection
        }
        
        if updateTable {
            addRow(0, section: section)
        }
    }
    
    private func addRow(_ row: Int, section: Int) {
        self.tableView.insertRows(at: [IndexPath(row: row, section: section)], with: BrowseViewController.AddAnimation)
    }
    
    private func removeRow(_ row: Int, section: Int) {
        self.tableView.deleteRows(at: [IndexPath(row: row, section: section)], with: BrowseViewController.DelAnimation)
    }
	
	private func remotePeerAppeared(_ peerID: MCPeerID) {
        addPeerIDToView(peerID, updateTable: true)
	}
	
	private func remotePeerDisappeared(_ peerID: MCPeerID) {
        if let idx = (matchedPeers.index { $0.peerID == peerID }) {
            matchedPeers.remove(at: idx)
            if matchedPeers.count == 0 {
                tableView.reloadSections(IndexSet(integer: BrowseViewController.MatchedPeersSection), with: .automatic)
            } else {
                removeRow(idx, section: BrowseViewController.MatchedPeersSection)
            }
        } else if let idx = (newPeers.index { $0 == peerID }) {
            newPeers.remove(at: idx)
            removeRow(idx, section: BrowseViewController.NewPeersSection)
        } else if let idx = (inFilterPeers.index { $0.peerID == peerID }) {
            inFilterPeers.remove(at: idx)
            removeRow(idx, section: BrowseViewController.InFilterPeersSection)
        } else if let idx = (outFilterPeers.index { $0.peerID == peerID }) {
            outFilterPeers.remove(at: idx)
            removeRow(idx, section: BrowseViewController.OutFilterPeersSection)
        }
	}
    
    private func connectionChangedState(_ nowOnline: Bool) {
        tableView.reloadData()
        if nowOnline {
            networkButton.setTitle(NSLocalizedString("Go Offline", comment: "Toggle to offline mode. Also title in browse view."), for: UIControlState())
        } else {
            networkButton.setTitle(NSLocalizedString("Go Online", comment: "Toggle to online mode. Also title in browse view."), for: UIControlState())
            clearCache()
        }
//        networkButton.frame = CGRect(origin: CGPoint.zero, size: networkButton.intrinsicContentSize)
        tableView.isScrollEnabled = nowOnline
    }
    
    private func peerInfoLoaded(_ peer: PeerInfo) {
        if let idx = (newPeers.index { $0 == peer.peerID }) {
            newPeers.remove(at: idx)
            let oldPath = IndexPath(row: idx, section: BrowseViewController.NewPeersSection)
            let newPath = IndexPath(row: 0, section: addPeerToView(peer))
            tableView.moveRow(at: oldPath, to: newPath)
            tableView.reloadRows(at: [newPath], with: .automatic)
        }
    }
    
    private func pinMatchOccured(_ peer: PeerInfo) {
        assert(matchedPeers.index(of: peer) == nil, "The following code assumes it is executed only once for one peer at maximum. If this is not correct any more, a guard check of this assertion would be enough here (since then nothing has to be done).")
        
        var _row: Int? = nil
        var _sec: Int? = nil
        
        if let idx = (newPeers.index { $0 == peer.peerID }) {
            newPeers.remove(at: idx)
            _row = idx
            _sec = BrowseViewController.NewPeersSection
        } else if let idx = (inFilterPeers.index { $0 == peer }) {
            inFilterPeers.remove(at: idx)
            _row = idx
            _sec = BrowseViewController.InFilterPeersSection
        } else if let idx = (outFilterPeers.index { $0 == peer }) {
            outFilterPeers.remove(at: idx)
            _row = idx
            _sec = BrowseViewController.OutFilterPeersSection
        }
        
        if let row = _row {
            let oldPath = IndexPath(row: row, section: _sec!)
            let newPath = IndexPath(row: 0, section: addPeerToView(peer))
            tableView.moveRow(at: oldPath, to: newPath)
        }
    }
    
    private func clearCache() {
        tableView.reloadData()
        matchedPeers.removeAll()
        newPeers.removeAll()
        inFilterPeers.removeAll()
        outFilterPeers.removeAll()
        tableView.reloadData()
    }
}

final class OfflineTableViewCell: UITableViewCell {
    @IBOutlet weak var peersMetLabel: UILabel!
}
