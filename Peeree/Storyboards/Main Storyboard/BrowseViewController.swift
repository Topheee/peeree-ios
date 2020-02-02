//
//  BrowseViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class BrowseViewController: UITableViewController {
    @IBOutlet private weak var networkButton: UIButton!

	private static let PresentMeSegueID = "presentMeViewController"
    private static let PeerDisplayCellID = "peerDisplayCell"
    private static let OfflineModeCellID = "placeholderCell"
    private static let AddAnimation = UITableView.RowAnimation.automatic
    private static let DelAnimation = UITableView.RowAnimation.automatic
    
    enum PeersSection: Int {
        case matched = 0, inFilter, outFilter
    }
    
    static let ViewPeerSegueID = "ViewPeerSegue"
    
    static var instance: BrowseViewController?
	
	private var activePlaceholderCell: UITableViewCell? = nil
	private var theGesturer: UIGestureRecognizer? = nil // we need to keep a reference to it
	
	private var peerCache: [[PeerInfo]] = [[], [], []]
	private var managerCache: [[PeerManager]] = [[], [], []]
    
    private var notificationObservers: [NSObjectProtocol] = []
    
    private var placeholderCellActive: Bool {
        var peerAvailable = false
        for peerArray in peerCache {
            peerAvailable = peerAvailable || peerArray.count > 0
        }
        return !PeeringController.shared.peering || !peerAvailable
    }
	
	@IBAction func unwindToBrowseViewController(_ segue: UIStoryboardSegue) { }
	
	@IBAction func toggleNetwork(_ sender: AnyObject) {
        guard AccountController.shared.accountExists else {
			InAppNotificationViewController.presentGlobally(title: NSLocalizedString("Peeree Identity Needed", comment: "Title of alert when the user wants to go online but lacks an account and it's creation failed."), message: NSLocalizedString("You need a unique Peeree identity to participate.", comment: "The user lacks a Peeree account")) {
				self.performSegue(withIdentifier: BrowseViewController.PresentMeSegueID, sender: self)
			}
			return
		}
		if PeeringController.shared.remote.isBluetoothOn {
			PeeringController.shared.peering = !PeeringController.shared.peering
		} else {
			UIApplication.shared.openURL(URL(string: UIApplication.openSettingsURLString)!)
		}
    }
    
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: sender)
		defer {
			// we need to defer this, otherwise tableView.indexPath(for: tappedCell) doesn't work
			navigationController?.setNavigationBarHidden(false, animated: true)
		}
		guard let personDetailVC = segue.destination as? PersonDetailViewController else { return }
        guard let tappedCell = sender as? UITableViewCell else {
			if let peerID = sender as? PeerID {
            	personDetailVC.peerManager = PeeringController.shared.manager(for: peerID)
			}
            return
        }
        guard tappedCell.reuseIdentifier == BrowseViewController.PeerDisplayCellID else { return }
        guard let cellPath = tableView.indexPath(for: tappedCell) else { return }
		personDetailVC.peerManager = managerCache[cellPath.section][cellPath.row]
	}
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        connectionChangedState(PeeringController.shared.peering)
        
        notificationObservers.append(PeeringController.Notifications.peerAppeared.addPeerObserver { [weak self] (peerID, _) in self?.peerAppeared(peerID) })
        notificationObservers.append(PeeringController.Notifications.peerDisappeared.addPeerObserver { [weak self] (peerID, _) in self?.peerDisappeared(peerID) })
        notificationObservers.append(PeeringController.Notifications.connectionChangedState.addObserver { [weak self] notification in
            self?.connectionChangedState(PeeringController.shared.peering)
        })
		notificationObservers.append(PeerManager.Notifications.unreadMessageCountChanged.addPeerObserver { [weak self] peerID, _  in
			self?.messageReceivedOrRead(from: peerID)
		})
        
		notificationObservers.append(AccountController.Notifications.pinMatch.addPeerObserver { [weak self] (peerID, _) in self?.pinMatchOccurred(peerID: peerID) })
        notificationObservers.append(AccountController.Notifications.pinned.addPeerObserver { [weak self] (peerID, _) in self?.reload(peerID: peerID) })
        notificationObservers.append(PeerManager.Notifications.verified.addPeerObserver { [weak self] (peerID, _) in self?.reload(peerID: peerID) })
        notificationObservers.append(PeerManager.Notifications.verificationFailed.addPeerObserver { [weak self] (peerID, _) in self?.reload(peerID: peerID) })
        notificationObservers.append(PeerManager.Notifications.pictureLoaded.addPeerObserver { [weak self] (peerID, _) in self?.reload(peerID: peerID) })
        
        notificationObservers.append(BrowseFilterSettings.Notifications.filterChanged.addObserver { [weak self] _ in
            guard let strongSelf = self else { return }
            
            let cacheCount = strongSelf.peerCache.count
            for i in 0..<cacheCount {
                strongSelf.peerCache[i].removeAll()
				strongSelf.managerCache[i].removeAll()
            }
            
            let peerManager = PeeringController.shared.remote
            for peerID in peerManager.availablePeers {
                strongSelf.addToView(peerID: peerID, updateTable: false)
            }
            strongSelf.tableView.reloadData()
        })

		tableView.scrollsToTop = true
    }
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
        BrowseViewController.instance = self
        tableView.reloadData()
		
        tabBarController?.tabBar.items?[0].badgeValue = nil
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        networkButton.layer.cornerRadius = networkButton.bounds.height / 2.0
        networkButton.tintColor = AppTheme.tintColor
		if #available(iOS 13, *) {
			// WHAT THE FUCK WHY DOES IT NOT WORK: networkButton.backgroundColor = AppTheme.backgroundColor
			networkButton.backgroundColor = self.traitCollection.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
		} else {
			networkButton.backgroundColor = UIColor.white
		}
	}
	
	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		if #available(iOS 13, *) {
			// WHAT THE FUCK WHY DOES IT NOT WORK: networkButton.backgroundColor = AppTheme.backgroundColor
			networkButton.backgroundColor = self.traitCollection.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
		}
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
        BrowseViewController.instance = nil
	}
    
    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: UITableViewDataSource
	
	override func numberOfSections(in tableView: UITableView) -> Int {
        return !placeholderCellActive ? peerCache.count : 1
	}
	
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if placeholderCellActive {
            return 1
        } else {
            return peerCache[section].count
        }
	}
	
	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		tableView.isScrollEnabled = !placeholderCellActive
        guard !placeholderCellActive else {
// TODO dequeueReusableCell (in both variants) for whatever reason causes EXC_BAD_ACCESS on ipad:
//			guard let cell = tableView.dequeueReusableCell(withIdentifier: BrowseViewController.OfflineModeCellID, for: indexPath) as? OfflineTableViewCell else {
			guard let cell = tableView.dequeueReusableCell(withIdentifier: BrowseViewController.OfflineModeCellID) as? OfflineTableViewCell else {
                assertionFailure("well that didn't work out so well")
                return UITableViewCell()
            }
			activePlaceholderCell = cell
			theGesturer.map { cell.gestureRecognizers = [$0] }
            
            if #available(iOS 11.0, *) {
                cell.frame.size.height = tableView.bounds.height - tableView.adjustedContentInset.bottom
            } else {
                cell.frame.size.height = tableView.bounds.height - tableView.contentInset.bottom
            }
			cell.setContent(mode: PeeringController.shared.peering ? .alone : .offline)
            return cell
        }
        
//        let cell = tableView.dequeueReusableCell(withIdentifier: BrowseViewController.PeerDisplayCellID, for: indexPath)
		let cell = tableView.dequeueReusableCell(withIdentifier: BrowseViewController.PeerDisplayCellID)!
		fill(cell: cell, peer: peerCache[indexPath.section][indexPath.row], manager: managerCache[indexPath.section][indexPath.row])
		return cell
	}
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard !placeholderCellActive else { return nil }
        guard let peerSection = PeersSection(rawValue: section) else { return super.tableView(tableView, titleForHeaderInSection: section) }
        
        switch peerSection {
        case .matched:
            return peerCache[0].count > 0 ? NSLocalizedString("Pin Matches", comment: "Header of table view section in browse view, which contains entries for pin matched peers.") : nil
        case .inFilter:
            return peerCache[1].count > 0 ? NSLocalizedString("People Around", comment: "Header of table view section in browse view, which contains entries for peers currently available on the network (so they are nere around).") : nil
        case .outFilter:
            return peerCache[2].count > 0 ? NSLocalizedString("Filtered People", comment: "Header of table view section in browse view, which contains entries for people who are most likely not interesting for the user because they did not pass his filter.") : nil
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if #available(iOS 11.0, *) {
            return !placeholderCellActive ? super.tableView(tableView, heightForRowAt: indexPath) : tableView.bounds.height - tableView.adjustedContentInset.bottom
        } else {
            return !placeholderCellActive ? super.tableView(tableView, heightForRowAt: indexPath) : tableView.bounds.height - tableView.contentInset.bottom
        }
    }
    
    func indexPath(of peerID: PeerID) -> IndexPath? {
        for i in 0..<peerCache.count  {
			let row = peerCache[i].firstIndex { $0.peerID == peerID }
            if row != nil {
                return IndexPath(row: row!, section: i)
            }
        }
        return nil
    }
	
	// MARK: UITableViewDelegate
	
	@available(iOS 11.0, *)
	override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		guard !placeholderCellActive && indexPath.section != PeersSection.matched.rawValue else { return nil }
		let peer = self.peerCache[indexPath.section][indexPath.row]
		guard !peer.pinned else { return nil }
		let pinAction = UIContextualAction(style: .normal, title: NSLocalizedString("Pin", comment: "The user wants to pin a person")) { (action, view, completion) in
			AccountController.shared.pin(peer)
			completion(true)
		}
		return UISwipeActionsConfiguration(actions: [pinAction])
	}
	
	// MARK: UIScollViewDelegate
	
	@available(iOS 11.0, *)
	override func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
		// throws 'unrecognized selector': super.scrollViewDidChangeAdjustedContentInset(scrollView)
		
		theGesturer = activePlaceholderCell?.gestureRecognizers?.first ?? theGesturer
		activePlaceholderCell?.gestureRecognizers?.removeAll()
		if placeholderCellActive {
			DispatchQueue.main.async {
				self.tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .fade)
			}
		}
	}
    
    // MARK: Private Methods
    
	private func fill(cell: UITableViewCell, peer: PeerInfo, manager: PeerManager) {
		cell.textLabel!.highlightedTextColor = AppTheme.tintColor
        cell.textLabel!.text = peer.nickname
        cell.detailTextLabel!.text = peer.summary
        guard let imageView = cell.imageView else { assertionFailure(); return }
        imageView.image = manager.picture ?? (peer.hasPicture ? #imageLiteral(resourceName: "PortraitPlaceholder") : #imageLiteral(resourceName: "PortraitUnavailable"))
        guard let originalImageSize = imageView.image?.size else { assertionFailure(); return }
        
        let minImageEdgeLength = min(originalImageSize.height, originalImageSize.width)
        guard let croppedImage = imageView.image?.cropped(to: CGRect(x: (originalImageSize.width - minImageEdgeLength) / 2, y: (originalImageSize.height - minImageEdgeLength) / 2, width: minImageEdgeLength, height: minImageEdgeLength)) else { assertionFailure(); return }
        
        let imageRect = CGRect(squareEdgeLength: cell.contentView.marginFrame.height)
        
        UIGraphicsBeginImageContextWithOptions(CGSize(squareEdgeLength: cell.contentView.marginFrame.height), true, UIScreen.main.scale)        
        AppTheme.backgroundColor.setFill()
        UIRectFill(imageRect)
        croppedImage.draw(in: imageRect)
        imageView.image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        let maskView = CircleMaskView(maskedView: imageView)
        maskView.frame = imageRect // Fix: imageView's size was (1, 1) when returning from person view
        if #available(iOS 11.0, *) {
            imageView.accessibilityIgnoresInvertColors = manager.picture != nil
        }
    }
    
	private func addToCache(peer: PeerInfo, manager: PeerManager) -> Int {
        if peer.pinMatched {
            peerCache[PeersSection.matched.rawValue].insert(peer, at: 0)
			managerCache[PeersSection.matched.rawValue].insert(manager, at: 0)
            return PeersSection.matched.rawValue
        } else if BrowseFilterSettings.shared.check(peer: peer) {
            peerCache[PeersSection.inFilter.rawValue].insert(peer, at: 0)
			managerCache[PeersSection.inFilter.rawValue].insert(manager, at: 0)
            return PeersSection.inFilter.rawValue
        } else {
            peerCache[PeersSection.outFilter.rawValue].insert(peer, at: 0)
			managerCache[PeersSection.outFilter.rawValue].insert(manager, at: 0)
            return PeersSection.outFilter.rawValue
        }
    }
    
    private func addToView(peerID: PeerID, updateTable: Bool) {
		let manager = PeeringController.shared.manager(for: peerID)
        guard let peer = manager.peerInfo else {
            assertionFailure()
            return
        }
        
        let placeHolderWasActive = placeholderCellActive
		let section = addToCache(peer: peer, manager: manager)
        
        if updateTable {
            if placeHolderWasActive {
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
	
	private func peerAppeared(_ peerID: PeerID) {
        addToView(peerID: peerID, updateTable: true)
	}
	
    private func peerDisappeared(_ peerID: PeerID) {
        guard let peerPath = indexPath(of: peerID) else {
            if PeeringController.shared.peering {
                NSLog("WARNING: Unknown peer \(peerID.uuidString) disappeared")
            }
            return
        }
        
        let wasOne = peerCache[peerPath.section].count == 1
        peerCache[peerPath.section].remove(at: peerPath.row)
		managerCache[peerPath.section].remove(at: peerPath.row)
        
        if wasOne && placeholderCellActive {
            tableView.reloadData()
        } else {
            remove(row: peerPath.row, section: peerPath.section)
        }
	}
	
	private func messageReceivedOrRead(from peerID: PeerID) {
		guard let peerPath = indexPath(of: peerID) else {
			NSLog("WARNING: Received message from non-presented peer \(peerID.uuidString)")
			return
		}
		tableView.reloadRows(at: [peerPath], with: .automatic)
	}
    
    private func connectionChangedState(_ nowOnline: Bool) {
        tableView.reloadData()
        if nowOnline {
            networkButton.setTitle(NSLocalizedString("Go Offline", comment: "Toggle to offline mode. Also title in browse view."), for: [])
        } else {
            networkButton.setTitle(NSLocalizedString("Go Online", comment: "Toggle to online mode. Also title in browse view."), for: [])
            
            for i in 0..<peerCache.count {
                peerCache[i].removeAll()
				managerCache[i].removeAll()
            }
            tableView.reloadData()
        }
        networkButton.setNeedsLayout()
        tableView.isScrollEnabled = nowOnline
    }
    
    private func reload(peerID: PeerID) {
        guard let indexPath = indexPath(of: peerID), let peer = managerCache[indexPath.section][indexPath.row].peerInfo else { return }
        
        // we have to refresh our cache if a peer changes - PeerInfos are structs!
        peerCache[indexPath.section][indexPath.row] = peer
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
    
    private func pinMatchOccurred(peerID: PeerID) {
		let manager = PeeringController.shared.manager(for: peerID)
		guard let peer = manager.peerInfo else { return }
        assert(peerCache[PeersSection.matched.rawValue].firstIndex(of: peer) == nil, "The following code assumes it is executed only once for one peer at maximum. If this is not correct any more, a guard check of this assertion would be enough here (since then nothing has to be done).")
        
        var _row: Int? = nil
        var _sec: Int? = nil
        var wasOne = false
        
        for section in [PeersSection.outFilter.rawValue, PeersSection.inFilter.rawValue] {
            if let idx = peerCache[section].firstIndex(of: peer) {
                peerCache[section].remove(at: idx)
				managerCache[section].remove(at: idx)
                wasOne = peerCache[section].count == 0
                _row = idx
                _sec = section
                break
            }
        }
        
        guard let row = _row else { return }
        
        let oldPath = IndexPath(row: row, section: _sec!)
		let newPath = IndexPath(row: 0, section: addToCache(peer: peer, manager: manager))
        tableView.moveRow(at: oldPath, to: newPath)
        tableView.scrollToRow(at: newPath, at: .none, animated: true)
        tableView.reloadRows(at: [newPath], with: .automatic)
        if wasOne {
            tableView.reloadSections(IndexSet(integer: _sec!), with: .automatic)
        }
    }
}

final class OfflineTableViewCell: UITableViewCell {
    @IBOutlet private weak var headLabel: UILabel!
    @IBOutlet private weak var subheadLabel: UILabel!
	@IBOutlet private weak var vibrancyEffectView: UIVisualEffectView!
	@IBOutlet private weak var blurEffectView: UIVisualEffectView!
	
	private var navigationBarTimer: Timer?
	
	enum Mode { case offline, alone }
	
	func setContent(mode: Mode) {
		switch mode {
		case .alone:
			headLabel.text = NSLocalizedString("Looking out…", comment: "Heading of the placeholder shown in browse view if no peers are around.")
			subheadLabel.text = NSLocalizedString("No Peeree users around.", comment: "Subhead of the placeholder shown in browse view if no peers are around.")
			let blurEffect: UIBlurEffect
			if #available(iOS 13.0, *) {
				subheadLabel.textColor = UIColor.label
				blurEffect = UIBlurEffect(style: .systemMaterial)
			} else {
				subheadLabel.textColor = UIColor.black
				blurEffect = UIBlurEffect(style: .extraLight)
			}
			blurEffectView.effect = blurEffect
			vibrancyEffectView.effect = UIVibrancyEffect(blurEffect: blurEffect)
			
			if #available(iOS 11.0, *) {
				guard ProcessInfo.processInfo.thermalState != .critical else { return }
			}
			let emitterLayer = CAEmitterLayer()
			
			emitterLayer.emitterPosition = frame.center
			
			let emitterCell = CAEmitterCell()
			emitterCell.birthRate = 7
			emitterCell.lifetime = 22
			emitterCell.velocity = 50
			emitterCell.scale = 0.035
			
			emitterCell.emissionRange = CGFloat.pi * 2.0
			emitterCell.contents = #imageLiteral(resourceName: "PortraitUnavailable").cgImage
			emitterCell.color = AppTheme.tintColor.cgColor
			
			emitterLayer.emitterCells = [emitterCell]
			
			let backgroundView = UIView(frame: bounds)
			backgroundView.clipsToBounds = true
			backgroundView.layer.addSublayer(emitterLayer)
			self.backgroundView = backgroundView
		case .offline:
			headLabel.text = NSLocalizedString("Offline Mode", comment: "Heading of the offline mode placeholder shown in browse view.")
			if PeeringController.shared.remote.isBluetoothOn {
				subheadLabel.text = NSLocalizedString("Tap to go online", comment: "Subhead of the offline mode placeholder shown in browse view when Bluetooth is on.")
			} else {
				subheadLabel.text = NSLocalizedString("Turn on Bluetooth to go online.", comment: "Subhead of the offline mode placeholder shown in browse view when Bluetooth is off.")
			}
			subheadLabel.textColor = AppTheme.tintColor
			vibrancyEffectView.effect = nil
			blurEffectView.effect = nil
			
			backgroundView = nil
		}
	}
}
