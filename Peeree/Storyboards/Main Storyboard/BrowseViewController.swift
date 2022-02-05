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
	private static let MaxRememberedHours = 24

	private enum TableSection: Int {
		case inFilter = 0, outFilter
	}
	
	static let ViewPeerSegueID = "ViewPeerSegue"

	/// Data source for `tableView`.
	private var viewCache: [[PeerViewModel]] = [[], []]

	private var notificationObservers: [NSObjectProtocol] = []
	
	private var placeholderCellActive: Bool {
		var peerAvailable = false
		for peerArray in viewCache {
			peerAvailable = peerAvailable || peerArray.count > 0
		}
		return !peerAvailable || !PeeringController.shared.peering
	}
	
	@IBAction func unwindToBrowseViewController(_ segue: UIStoryboardSegue) { }
	
	@IBAction func toggleNetwork(_ sender: AnyObject) {
		if PeeringController.shared.isBluetoothOn {
			PeeringController.shared.peering = !PeeringController.shared.peering
			AccountController.shared.refreshBlockedContent { error in
				InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Objectionable Content Refresh Failed", comment: "Title of alert when the remote API call to refresh objectionable portrait hashes failed."))
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
		peerVC.peerID = viewCache[cellPath.section][cellPath.row].peerID
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		connectionChangedState(PeeringController.shared.peering)
		
		notificationObservers.append(PeeringController.Notifications.peerAppeared.addAnyPeerObserver { [weak self] (peerID, notification) in
			let again = notification.userInfo?[PeeringController.NotificationInfoKey.again.rawValue] as? Bool
			self?.peerAppeared(peerID, again: again ?? false)
		})
		notificationObservers.append(PeeringController.Notifications.peerDisappeared.addAnyPeerObserver { [weak self] (peerID, _) in self?.peerDisappeared(peerID) })
		notificationObservers.append(PeeringController.Notifications.connectionChangedState.addObserver { [weak self] notification in
			self?.connectionChangedState((notification.userInfo?[PeeringController.NotificationInfoKey.connectionState.rawValue] as? NSNumber)?.boolValue ?? PeeringController.shared.peering)
		})
		notificationObservers.append(PeeringController.Notifications.persistedPeersLoadedFromDisk.addObserver { [weak self] _ in
			self?.updateCache()
		})

		let reloadBlock: (PeerID, Notification) -> Void = { [weak self] (peerID, _) in self?.reload(peerID: peerID) }
		notificationObservers.append(AccountController.Notifications.pinMatch.addAnyPeerObserver(usingBlock: reloadBlock))
		notificationObservers.append(AccountController.Notifications.pinned.addAnyPeerObserver(usingBlock: reloadBlock))
		notificationObservers.append(PeerViewModel.NotificationName.pictureLoaded.addAnyPeerObserver(usingBlock: reloadBlock))

		notificationObservers.append(BrowseFilterSettings.Notifications.filterChanged.addObserver { [weak self] _ in
			self?.updateCache()
		})

		tableView.scrollsToTop = true
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

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

	deinit {
		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
		}
	}
	
	// MARK: UITableViewDataSource
	
	override func numberOfSections(in tableView: UITableView) -> Int {
		return placeholderCellActive ? 1 : viewCache.count
	}
	
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return placeholderCellActive ? 1 : viewCache[section].count
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

		guard let cell = tableView.dequeueReusableCell(withIdentifier: BrowseViewController.PeerDisplayCellID) as? PeerTableViewCell else {
			assertionFailure("well that didn't work out so well2")
			return UITableViewCell()
		}

		let model = viewCache[indexPath.section][indexPath.row]
		cell.fill(with: model)

		// load the picture of the peer from disk once it is displayed
		if model.picture == nil && model.peer.info.hasPicture {
			PeeringController.shared.interact(with: model.peerID) { interaction in
				interaction.loadLocalPicture()
			}
		}

		return cell
	}
	
	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		guard !placeholderCellActive, viewCache[section].count > 0, let peerSection = TableSection(rawValue: section) else {
			return super.tableView(tableView, titleForHeaderInSection: section)
		}
		
		switch peerSection {
		case .inFilter:
			return NSLocalizedString("People Around", comment: "Header of table view section in browse view, which contains entries for peers currently available on the network (so they are hear around).")
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

	/// Finds index of `peerID` in the `section` subarray of `viewCache`.
	private func row(of peerID: PeerID, inSection section: Int) -> Int? {
		return viewCache[section].firstIndex { $0.peerID == peerID }
	}

	private func indexPath(of peerID: PeerID) -> IndexPath? {
		for i in 0..<viewCache.count  {
			if let row = row(of: peerID, inSection: i) {
				return IndexPath(row: row, section: i)
			}
		}
		return nil
	}
	
	// MARK: UITableViewDelegate
	
	@available(iOS 11.0, *)
	override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		guard !placeholderCellActive else { return nil }

		let id = self.viewCache[indexPath.section][indexPath.row].peer.id
		if id.pinned {
			let unpinAction = UIContextualAction(style: .destructive, title: NSLocalizedString("Unpin", comment: "The user wants to unpin a person")) { (action, view, completion) in
				AccountController.shared.unpin(id: id)
				completion(true)
			}
			return UISwipeActionsConfiguration(actions: [unpinAction])
		} else {
			let pinAction = UIContextualAction(style: .normal, title: NSLocalizedString("Pin", comment: "The user wants to pin a person")) { (action, view, completion) in
				AccountController.shared.pin(id)
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

	/// Adds `model` to `viewCache` and returns the appropriate section.
	private func addToCache(model: PeerViewModel) -> Int {
		let section: TableSection = BrowseFilterSettings.shared.check(peer: model.peer) ? .inFilter : .outFilter
		viewCache[section.rawValue].insert(model, at: 0)
		return section.rawValue
	}

	/// Adds `model` to `viewCache` and updates `tableView`.
	private func addToView(model: PeerViewModel, updateTable: Bool) {
		let placeHolderWasActive = placeholderCellActive
		let section = addToCache(model: model)

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
		if indexPath(of: peerID) != nil {
			reload(peerID: peerID)
			return
		}
		addToView(model: PeerViewModelController.viewModel(of: peerID), updateTable: true)
	}
	
	private func peerDisappeared(_ peerID: PeerID) {
		reload(peerID: peerID)
	}
	
	private func connectionChangedState(_ nowOnline: Bool) {
		tableView.reloadData()
		if nowOnline {
			networkButton.setTitle(NSLocalizedString("Go Offline", comment: "Toggle to offline mode. Also title in browse view."), for: [])
			updateCache()
		} else {
			networkButton.setTitle(NSLocalizedString("Go Online", comment: "Toggle to online mode. Also title in browse view."), for: [])

			for i in 0..<viewCache.count {
				viewCache[i].removeAll()
			}
			tableView.reloadData()
		}
		networkButton.setNeedsLayout()
		tableView.isScrollEnabled = nowOnline
	}
	
	private func reload(peerID: PeerID) {
		guard let indexPath = indexPath(of: peerID), let oldSection = TableSection(rawValue: indexPath.section) else { return }

		// we have to refresh our cache if a peer changes - PeerInfos are structs!
		let newModel = PeerViewModelController.viewModel(of: peerID)
		if newModel.lastSeen == viewCache[indexPath.section][indexPath.row].lastSeen {
			viewCache[indexPath.section][indexPath.row] = newModel
			tableView.reloadRows(at: [indexPath], with: .automatic)
		} else {
			var newIndexPath = position(in: oldSection, lastSeen: newModel.lastSeen)
			// we assume that only the lastSeen attribute changed and nothing that affects the filter (s.t. the section keeps the same)
			let immediatelyAfterOrSameRange = indexPath.row...indexPath.row+1
			if immediatelyAfterOrSameRange.contains(newIndexPath.row) {
				viewCache[indexPath.section][indexPath.row] = newModel
				tableView.reloadRows(at: [indexPath], with: .automatic)
			} else {
				if newIndexPath.row > indexPath.row {
					newIndexPath.row -= 1
				}
				viewCache[indexPath.section].remove(at: indexPath.row)
				viewCache[indexPath.section].insert(newModel, at: newIndexPath.row)
				tableView.moveRow(at: indexPath, to: newIndexPath)
			}
		}
	}

	/// Calculates the position of a peer in the lastSeen-sorted section.
	private func position(in section: TableSection, lastSeen: Date) -> IndexPath {
		// we assume viewCache is sorted by lastSeen already
		var row = 0
		for model in viewCache[section.rawValue] {
			if lastSeen < model.lastSeen {
				return IndexPath(row: row, section: section.rawValue)
			}
			row += 1
		}
		return IndexPath(row: row, section: section.rawValue)
	}

	/// Populates `viewCache` from scratch.
	private func updateCache() {
		let now = Date()
		let cal = Calendar.current as NSCalendar
		let userPeerID = AccountController.shared.peerID
		var displayedModels = PeerViewModelController.viewModels.values.filter { model in
			let lastSeenAgoCalc = cal.components(NSCalendar.Unit.hour, from: model.lastSeen, to: now, options: []).hour
			let lastSeenAgo = lastSeenAgoCalc ?? BrowseViewController.MaxRememberedHours + 1
			return lastSeenAgo < BrowseViewController.MaxRememberedHours && model.peerID != userPeerID
		}
		displayedModels.sort { a, b in a.lastSeen > b.lastSeen }
		clearViewCache()
		for displayedModel in displayedModels {
			_ = addToCache(model: displayedModel)
		}
		self.tableView?.reloadData()
	}

	/// Removes all entries from the subarrays of `viewCache`.
	private func clearViewCache() {
		for i in 0..<viewCache.count { viewCache[i].removeAll() }
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
			if PeeringController.shared.isBluetoothOn {
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
