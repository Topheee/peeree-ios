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
    @IBOutlet private weak var networkButton: UIButton!
	
    private static let PeerDisplayCellID = "peerDisplayCell"
    private static let OfflineModeCellID = "placeholderCell"
    private static let AddAnimation = UITableViewRowAnimation.automatic
    private static let DelAnimation = UITableViewRowAnimation.automatic
    
    enum PeersSection: Int {
        case Matched = 0, New, InFilter, OutFilter
    }
    
    static let ViewPeerSegueID = "ViewPeerSegue"
    
    static var instance: BrowseViewController?
    
//    private var peerCache: [[MCPeerID]] = [[], [], [], []]
    private var matchedPeers: [PeerInfo] = []
    private var newPeers: [MCPeerID] = []
    private var inFilterPeers: [PeerInfo] = []
    private var outFilterPeers: [PeerInfo] = []
    
    private var notificationObservers: [NSObjectProtocol] = []
    
    private var placeholderCellActive: Bool {
        var peerAvailable = false
        for peerArray in [matchedPeers, inFilterPeers, outFilterPeers] {
            peerAvailable = peerAvailable || peerArray.count > 0
        }
        peerAvailable = peerAvailable || newPeers.count > 0
        return !RemotePeerManager.shared.peering || !peerAvailable
    }
	
	@IBAction func unwindToBrowseViewController(_ segue: UIStoryboardSegue) {
		
	}
	
    @IBAction func toggleNetwork(_ sender: AnyObject) {
        RemotePeerManager.shared.peering = !RemotePeerManager.shared.peering
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
        guard let section = PeersSection(rawValue: cellPath.section) else { return }
        
        switch section {
        case .Matched:
            personDetailVC.displayedPeerID = matchedPeers[cellPath.row].peerID
        case .New:
            personDetailVC.displayedPeerID = newPeers[cellPath.row]
        case .InFilter:
            personDetailVC.displayedPeerID = inFilterPeers[cellPath.row].peerID
        case .OutFilter:
            personDetailVC.displayedPeerID = outFilterPeers[cellPath.row].peerID
        }
	}
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.peerAppeared.addObserver { (notification) in
            if let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.peerID.rawValue] as? MCPeerID {
                self.peerAppeared(peerID)
            }
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.peerDisappeared.addObserver { notification in
            if let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.peerID.rawValue] as? MCPeerID {
                self.peerDisappeared(peerID)
            }
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.connectionChangedState.addObserver { notification in
            self.connectionChangedState(RemotePeerManager.shared.peering)
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.peerInfoLoaded.addObserver { notification in
            if let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.peerID.rawValue] as? MCPeerID {
                self.peerInfoLoaded(RemotePeerManager.shared.getPeerInfo(of: peerID)!)
            }
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.pictureLoaded.addObserver { (notification) in
            guard let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.peerID.rawValue] as? MCPeerID else { return }
            guard let peer = RemotePeerManager.shared.getPeerInfo(of: peerID) else { return }
            
            self.pictureLoaded(peer)
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.pinMatch.addObserver { notification in
            if let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.peerID.rawValue] as? MCPeerID {
                self.pinMatchOccured(RemotePeerManager.shared.getPeerInfo(of: peerID)!)
            }
        })
        
        notificationObservers.append(RemotePeerManager.NetworkNotification.pinned.addObserver { notification in
            if let peerID = notification.userInfo?[RemotePeerManager.NetworkNotificationKey.peerID.rawValue] as? MCPeerID {
                self.pinned(peer: peerID)
            }
        })
    }
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
        BrowseViewController.instance = self
//        tableView.tableFooterView = UIView(frame: CGRect.zero)
        RemotePeerManager.shared.availablePeers.accessQueue.sync {
            // we can access the set variable safely here since we are on the queue
            for peerID in RemotePeerManager.shared.availablePeers.set {
                self.addToView(peerID: peerID, updateTable: false)
            }
        }
        
		tableView.reloadData()
        connectionChangedState(RemotePeerManager.shared.peering)
		
        tabBarController?.tabBar.items?[0].badgeValue = nil
        UIApplication.shared.applicationIconBadgeNumber = 0
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        clearCache()
        BrowseViewController.instance = nil
	}
    
    // MARK: UITableView Data Source
	
	override func numberOfSections(in tableView: UITableView) -> Int {
        return !placeholderCellActive ? 4 : 1
	}
	
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard !placeholderCellActive else { return 1 }
        guard let peerSection = PeersSection(rawValue: section) else { return 0 }
        
        switch peerSection {
        case .Matched:
            return matchedPeers.count
        case .New:
            return newPeers.count
        case .InFilter:
            return inFilterPeers.count
        case .OutFilter:
            return outFilterPeers.count
        }
	}
	
	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !placeholderCellActive else {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: BrowseViewController.OfflineModeCellID) as? OfflineTableViewCell else {
                assertionFailure()
                return UITableViewCell()
            }
            
            cell.peersMetLabel.text = String(RemotePeerManager.shared.peersMet)
            if RemotePeerManager.shared.peering {
                cell.headLabel.text = NSLocalizedString("All Alone", comment: "Heading of the placeholder shown in browse view if no peers are around.")
                cell.subheadLabel.text = NSLocalizedString("No Peeree users around.", comment: "Subhead of the placeholder shown in browse view if no peers are around.")
            } else {
                cell.headLabel.text = NSLocalizedString("Offline Mode", comment: "Heading of the offline mode placeholder shown in browse view.")
                cell.subheadLabel.text = NSLocalizedString("You are invisible – and blind.", comment: "Subhead of the offline mode placeholder shown in browse view.")
            }
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: BrowseViewController.PeerDisplayCellID)!
        guard let peerSection = PeersSection(rawValue: indexPath.section) else {
            assertionFailure()
            return UITableViewCell()
        }
        
        switch peerSection {
        case .Matched:
            fill(cell: cell, peer: matchedPeers[indexPath.row])
        case .New:
            let peerID = newPeers[indexPath.row]
            cell.textLabel!.text = peerID.displayName
            cell.detailTextLabel!.text = ""
            cell.imageView?.image = nil
        case .InFilter:
            fill(cell: cell, peer: inFilterPeers[indexPath.row])
        case .OutFilter:
            fill(cell: cell, peer: outFilterPeers[indexPath.row])
        }
        
		return cell
	}
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard !placeholderCellActive else { return nil }
        guard let peerSection = PeersSection(rawValue: section) else { return super.tableView(tableView, titleForHeaderInSection: section) }
        
        switch peerSection {
        case .Matched:
            return matchedPeers.count > 0 ? NSLocalizedString("Matches", comment: "Header of table view section in browse view, which contains entries for pin matched peers.") : nil
        case .New:
            return newPeers.count > 0 ? NSLocalizedString("New People", comment: "Header of table view section in browse view, which contains entries for new users around whoose data has not been loaded yet.") : nil
        case .InFilter:
            return inFilterPeers.count > 0 ? NSLocalizedString("People Around", comment: "Header of table view section in browse view, which contains entries for peers currently available on the network (so they are nere around).") : nil
        case .OutFilter:
            return outFilterPeers.count > 0 ? NSLocalizedString("Filtered People", comment: "Header of table view section in browse view, which contains entries for people who are most likely not interesting for the user because they did not pass his filter.") : nil
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return !placeholderCellActive ? super.tableView(tableView, heightForRowAt: indexPath) : tableView.frame.height - (self.tabBarController?.tabBar.frame.height ?? 49) - (self.navigationController?.navigationBar.frame.height ?? 44) - UIApplication.shared.statusBarFrame.height
    }
    
    func indexPath(of peerID: MCPeerID) -> IndexPath? {
        guard let peer = RemotePeerManager.shared.getPeerInfo(of: peerID) else {
            guard let row = newPeers.index(of: peerID) else { return nil }
            return IndexPath(row: row, section: PeersSection.New.rawValue)
        }

        return indexPath(of: peer)
    }
    
    func indexPath(of peer: PeerInfo) -> IndexPath? {
        let array: [([PeerInfo], PeersSection)] = [(inFilterPeers, .InFilter), (outFilterPeers, .OutFilter), (matchedPeers, .Matched)]
        for a in array {
            let row = a.0.index(of: peer)
            if row != nil {
                return IndexPath(row: row!, section: a.1.rawValue)
            }
        }
        return nil
    }
    
    // MARK: Private Methods
    
    private func fill(cell: UITableViewCell, peer: PeerInfo) {
        cell.textLabel!.text = peer.peerID.displayName
        cell.detailTextLabel!.text = peer.summary
        guard let imageView = cell.imageView else { assertionFailure(); return }
        imageView.image = peer.picture ?? (peer.hasPicture ? UIImage(named: "PortraitPlaceholder") : UIImage(named: "PortraitUnavailable"))
        guard let originalImageSize = imageView.image?.size else { assertionFailure(); return }
        
        let minImageEdgeLength = min(originalImageSize.height, originalImageSize.width)
        guard let croppedImage = imageView.image?.cropped(to: CGRect(x: (originalImageSize.width - minImageEdgeLength) / 2, y: (originalImageSize.height - minImageEdgeLength) / 2, width: minImageEdgeLength, height: minImageEdgeLength)) else { assertionFailure(); return }
        
        UIGraphicsBeginImageContextWithOptions(CGSize(squareEdgeLength: cell.contentView.marginFrame.height), true, UIScreen.main.scale)
        let imageRect = CGRect(squareEdgeLength: cell.contentView.marginFrame.height)
        croppedImage.draw(in: imageRect)
//        imageView.image = autoreleasepool {
//            return UIGraphicsGetImageFromCurrentImageContext()
//        }
        imageView.image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        let maskView = CircleMaskView(maskedView: imageView)
        maskView.frame = imageRect // Fix: imageView's size was (1, 1) when returning from person view
    }
    
    private func addPeerToView(_ peer: PeerInfo) -> Int {
        if peer.pinMatched {
            matchedPeers.insert(peer, at: 0)
            return PeersSection.Matched.rawValue
        } else if BrowseFilterSettings.shared.check(peer: peer) {
            inFilterPeers.insert(peer, at: 0)
            return PeersSection.InFilter.rawValue
        } else {
            outFilterPeers.insert(peer, at: 0)
            return PeersSection.OutFilter.rawValue
        }
    }
    
    private func addToView(peerID: MCPeerID, updateTable: Bool) {
        let placeHolderWasActive = placeholderCellActive
        
        var section: Int
        if let peer = RemotePeerManager.shared.getPeerInfo(of: peerID) {
            section = addPeerToView(peer)
        } else {
            newPeers.insert(peerID, at: 0)
            section = PeersSection.New.rawValue
        }
        
        if updateTable {
            if placeHolderWasActive && !placeholderCellActive {
                tableView.reloadData()
            } else {
                add(row: 0, section: section)
            }
        }
    }
    
    private func add(row: Int, section: Int) {
        tableView.insertRows(at: [IndexPath(row: row, section: section)], with: BrowseViewController.AddAnimation)
    }
    
    private func remove(row: Int, section: Int) {
        tableView.deleteRows(at: [IndexPath(row: row, section: section)], with: BrowseViewController.DelAnimation)
    }
	
	private func peerAppeared(_ peerID: MCPeerID) {
        addToView(peerID: peerID, updateTable: true)
	}
	
    private func peerDisappeared(_ peerID: MCPeerID) {
        guard let peerPath = indexPath(of: peerID) else { return }
        guard let peerSection = PeersSection(rawValue: peerPath.section) else { return }
        
        var wasOne: Bool
        switch peerSection {
        case .Matched:
            wasOne = matchedPeers.count == 1
            matchedPeers.remove(at: peerPath.row)
        case .New:
            wasOne = newPeers.count == 1
            newPeers.remove(at: peerPath.row)
        case .InFilter:
            wasOne = inFilterPeers.count == 1
            inFilterPeers.remove(at: peerPath.row)
        case .OutFilter:
            wasOne = outFilterPeers.count == 1
            outFilterPeers.remove(at: peerPath.row)
        }
        
        if wasOne && placeholderCellActive {
            tableView.reloadData()
        } else {
            remove(row: peerPath.row, section: peerPath.section)
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
        networkButton.setNeedsLayout()
        tableView.isScrollEnabled = nowOnline
    }
    
    private func peerInfoLoaded(_ peer: PeerInfo) {
        guard let idx = (newPeers.index { $0 == peer.peerID }) else { return }
        
        newPeers.remove(at: idx)
        let oldPath = IndexPath(row: idx, section: PeersSection.New.rawValue)
        let newPath = IndexPath(row: 0, section: addPeerToView(peer))
        tableView.moveRow(at: oldPath, to: newPath)
        tableView.scrollToRow(at: newPath, at: .none, animated: true)
        tableView.reloadRows(at: [newPath], with: .automatic)
    }
    
    private func pictureLoaded(_ peer: PeerInfo) {
        guard let indexPath = indexPath(of: peer) else { return }
        guard let peerSection = PeersSection(rawValue: indexPath.section) else { return }
        
        // we have to refresh our cache if a peer changes - PeerInfos are structs!
        switch peerSection {
        case .Matched:
            matchedPeers[indexPath.row] = peer
        case .InFilter:
            inFilterPeers[indexPath.row] = peer
        case .OutFilter:
            outFilterPeers[indexPath.row] = peer
        case .New:
            assertionFailure()
        }
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
    
    private func pinned(peer peerID: MCPeerID) {
        guard let indexPath = indexPath(of: peerID) else { return }
        
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
    
    private func pinMatchOccured(_ peer: PeerInfo) {
        assert(matchedPeers.index(of: peer) == nil, "The following code assumes it is executed only once for one peer at maximum. If this is not correct any more, a guard check of this assertion would be enough here (since then nothing has to be done).")
        
        var _row: Int? = nil
        var _sec: Int? = nil
        
        if let idx = (newPeers.index { $0 == peer.peerID }) {
            newPeers.remove(at: idx)
            _row = idx
            _sec = PeersSection.New.rawValue
        } else if let idx = (inFilterPeers.index { $0 == peer }) {
            inFilterPeers.remove(at: idx)
            _row = idx
            _sec = PeersSection.InFilter.rawValue
        } else if let idx = (outFilterPeers.index { $0 == peer }) {
            outFilterPeers.remove(at: idx)
            _row = idx
            _sec = PeersSection.OutFilter.rawValue
        }
        
        if let row = _row {
            let oldPath = IndexPath(row: row, section: _sec!)
            let newPath = IndexPath(row: 0, section: addPeerToView(peer))
            tableView.moveRow(at: oldPath, to: newPath)
            tableView.scrollToRow(at: newPath, at: .none, animated: true)
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
    @IBOutlet weak var headLabel: UILabel!
    @IBOutlet weak var subheadLabel: UILabel!
    @IBOutlet weak var peersMetLabel: UILabel!
}
