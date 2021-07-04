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

	private static let PeerDisplayCellID = "peerDisplayCell"
	private static let OfflineModeCellID = "placeholderCell"
	private static let AddAnimation = UITableView.RowAnimation.automatic
	private static let DelAnimation = UITableView.RowAnimation.automatic
	
	enum PeersSection: Int {
		case inFilter = 0, recentlySeen, outFilter
	}
	
	static let ViewPeerSegueID = "ViewPeerSegue"
	
	static var instance: BrowseViewController?
	
	private var peerCache: [[PeerInfo]] = [[], [], [], []]
	private var managerCache: [[PeerManager]] = [[], [], [], []]
	
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
			InAppNotificationViewController.presentGlobally(title: NSLocalizedString("Peeree Identity Required", comment: "Title of alert when the user wants to go online but lacks an account and it's creation failed."), message: NSLocalizedString("Tap to create your Peeree identity.", comment: "The user lacks a Peeree account")) {
				(AppDelegate.shared.window?.rootViewController as? UITabBarController)?.selectedIndex = AppDelegate.MeTabBarIndex
			}
			return
		}
		if PeeringController.shared.remote.isBluetoothOn {
			PeeringController.shared.peering = !PeeringController.shared.peering
			AccountController.shared.refreshBlockedContent { error in
				AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Objectionable Content Refresh Failed", comment: "Title of alert when the remote API call to refresh objectionable portrait hashes failed."))
			}
			if #available(iOS 13.0, *) { HapticController.playHapticClick() }
		} else {
			UIApplication.shared.openURL(URL(string: UIApplication.openSettingsURLString)!)
		}
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: sender)
		guard let peerVC = segue.destination as? PeerObserverContainer else { return }
		guard let tappedCell = sender as? UITableViewCell else {
			if let peerID = sender as? PeerID {
				peerVC.peerID = peerID
			}
			return
		}
		guard let cellPath = tableView.indexPath(for: tappedCell) else { return }
		peerVC.peerID = managerCache[cellPath.section][cellPath.row].peerID
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		connectionChangedState(PeeringController.shared.peering)
		
		notificationObservers.append(PeeringController.Notifications.peerAppeared.addPeerObserver { [weak self] (peerID, notification) in
			let again = notification.userInfo?[PeeringController.NotificationInfoKey.again.rawValue] as? Bool
			self?.peerAppeared(peerID, again: again ?? false)
		})
		notificationObservers.append(PeeringController.Notifications.peerDisappeared.addPeerObserver { [weak self] (peerID, _) in self?.peerDisappeared(peerID) })
		notificationObservers.append(PeeringController.Notifications.connectionChangedState.addObserver { [weak self] notification in
			self?.connectionChangedState(PeeringController.shared.peering)
		})

		let reloadBlock: (PeerID, Notification) -> Void = { [weak self] (peerID, _) in self?.reload(peerID: peerID) }
		notificationObservers.append(AccountController.Notifications.pinMatch.addPeerObserver(usingBlock: reloadBlock))
		notificationObservers.append(AccountController.Notifications.pinned.addPeerObserver(usingBlock: reloadBlock))
		notificationObservers.append(PeerManager.Notifications.verified.addPeerObserver(usingBlock: reloadBlock))
		notificationObservers.append(PeerManager.Notifications.verificationFailed.addPeerObserver(usingBlock: reloadBlock))
		notificationObservers.append(PeerManager.Notifications.pictureLoaded.addPeerObserver(usingBlock: reloadBlock))

		notificationObservers.append(BrowseFilterSettings.Notifications.filterChanged.addObserver { [weak self] _ in
			guard let strongSelf = self else { return }
			
			let cacheCount = strongSelf.peerCache.count
			for i in 0..<cacheCount {
				guard i != PeersSection.recentlySeen.rawValue else { continue }
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
		return placeholderCellActive ? 1 : peerCache.count
	}
	
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return placeholderCellActive ? 1 : peerCache[section].count
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
			let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(toggleNetwork(_:)))
			cell.addGestureRecognizer(gestureRecognizer)
			
			if #available(iOS 11.0, *) {
				cell.frame.size.height = tableView.bounds.height - tableView.adjustedContentInset.bottom
			} else {
				cell.frame.size.height = tableView.bounds.height - tableView.contentInset.bottom
			}
			cell.setContent(mode: PeeringController.shared.peering ? .alone : .offline)
			return cell
		}

		let cell: UITableViewCell = tableView.dequeueReusableCell(withIdentifier: BrowseViewController.PeerDisplayCellID)!
		(cell as? PeerTableViewCell)?.fill(with: managerCache[indexPath.section][indexPath.row])
		return cell
	}
	
	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		guard !placeholderCellActive, peerCache[section].count > 0 else { return nil }
		guard let peerSection = PeersSection(rawValue: section) else { return super.tableView(tableView, titleForHeaderInSection: section) }
		
		switch peerSection {
		case .inFilter:
			return NSLocalizedString("People Around", comment: "Header of table view section in browse view, which contains entries for peers currently available on the network (so they are hear around).")
		case .recentlySeen:
			return NSLocalizedString("Last Seen Recently", comment: "Header of table view section in browse view, which contains entries for peers recently available on the network (so they are probably around).")
		case .outFilter:
			return NSLocalizedString("Filtered People", comment: "Header of table view section in browse view, which contains entries for people who are most likely not interesting for the user because they did not pass his filter.")
		}
	}
	
	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		if #available(iOS 11.0, *) {
			return !placeholderCellActive ? super.tableView(tableView, heightForRowAt: indexPath) : tableView.bounds.height - tableView.adjustedContentInset.bottom
		} else {
			return !placeholderCellActive ? super.tableView(tableView, heightForRowAt: indexPath) : tableView.bounds.height - tableView.contentInset.bottom
		}
	}
	
	private func indexPath(of peerID: PeerID) -> IndexPath? {
		for i in 0..<peerCache.count  {
			if let row = peerCache[i].firstIndex(where: { $0.peerID == peerID }) {
				return IndexPath(row: row, section: i)
			}
		}
		return nil
	}
	
	// MARK: UITableViewDelegate
	
	@available(iOS 11.0, *)
	override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		guard !placeholderCellActive else { return nil }
		let peer = self.peerCache[indexPath.section][indexPath.row]
		if peer.pinned {
			let unpinAction = UIContextualAction(style: .destructive, title: NSLocalizedString("Unpin", comment: "The user wants to unpin a person")) { (action, view, completion) in
				AccountController.shared.unpin(peer: peer)
				completion(true)
			}
			return UISwipeActionsConfiguration(actions: [unpinAction])
		} else {
			let pinAction = UIContextualAction(style: .normal, title: NSLocalizedString("Pin", comment: "The user wants to pin a person")) { (action, view, completion) in
				AccountController.shared.pin(peer)
				completion(true)
			}
			pinAction.backgroundColor = AppTheme.tintColor
			return UISwipeActionsConfiguration(actions: [pinAction])
		}
	}
	
	// MARK: UIScollViewDelegate
	
	@available(iOS 11.0, *)
	override func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
		// throws 'unrecognized selector': super.scrollViewDidChangeAdjustedContentInset(scrollView)

		DispatchQueue.main.async {
			if self.placeholderCellActive {
				self.tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .fade)
			}
		}
	}
	
	// MARK: Private Methods
	
	private func addToCache(peer: PeerInfo, manager: PeerManager) -> Int {
		let section: PeersSection
		if !manager.isAvailable {
			section = .recentlySeen
		} else if BrowseFilterSettings.shared.check(peer: peer) {
			section = .inFilter
		} else {
			section = .outFilter
		}
		peerCache[section.rawValue].insert(peer, at: 0)
		managerCache[section.rawValue].insert(manager, at: 0)
		return section.rawValue
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
	
	private func peerAppeared(_ peerID: PeerID, again: Bool) {
		addToView(peerID: peerID, updateTable: true)
		if again {
			if let row = peerCache[PeersSection.recentlySeen.rawValue].firstIndex(where: { $0.peerID == peerID }) {
				peerCache[PeersSection.recentlySeen.rawValue].remove(at: row)
				managerCache[PeersSection.recentlySeen.rawValue].remove(at: row)
				remove(row: row, section: PeersSection.recentlySeen.rawValue)
			}
		}
	}
	
	private func peerDisappeared(_ peerID: PeerID) {
		guard let peerPath = indexPath(of: peerID) else {
			if PeeringController.shared.peering {
				NSLog("WARN: Unknown peer \(peerID.uuidString) disappeared.")
			}
			return
		}
		
		peerCache[peerPath.section].remove(at: peerPath.row)
		managerCache[peerPath.section].remove(at: peerPath.row)
		
		if !(peerCache[PeersSection.recentlySeen.rawValue].contains { $0.peerID == peerID }) {
			addToView(peerID: peerID, updateTable: false)
			if !(peerCache[PeersSection.recentlySeen.rawValue].contains { $0.peerID == peerID }) {
				NSLog("ERROR: YIKES!")
				tableView.reloadData()
			} else {
				tableView.moveRow(at: peerPath, to: IndexPath(row: 0, section: PeersSection.recentlySeen.rawValue))
				if peerCache[peerPath.section].count == 0 { tableView.reloadSections(IndexSet(integer: peerPath.section), with: .automatic) }
			}
		} else {
			remove(row: peerPath.row, section: peerPath.section)
		}
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
}

final class OfflineTableViewCell: UITableViewCell {
	@IBOutlet private weak var headLabel: UILabel!
	@IBOutlet private weak var subheadLabel: UILabel!
	@IBOutlet private weak var vibrancyEffectView: UIVisualEffectView!
	@IBOutlet private weak var blurEffectView: UIVisualEffectView!

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
