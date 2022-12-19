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

	// Shortcut to `PeerViewModelController.shared`.
	private let viewModel = PeerViewModelController.shared

	/// Data source for `tableView`.
	private var table: [[(PeerID, Date)]] = [[], []]

	/// Currently applied filter.
	private var filter = BrowseFilter()

	private var notificationObservers: [NSObjectProtocol] = []
	
	private var placeholderCellActive: Bool {
		var peerAvailable = false
		for peerArray in table {
			peerAvailable = peerAvailable || peerArray.count > 0
		}
#if SHOWCASE
		return !peerAvailable
#else
		return !peerAvailable || !viewModel.peering
#endif
	}
	
	@IBAction func unwindToBrowseViewController(_ segue: UIStoryboardSegue) { }

	@IBAction func toggleNetwork(_ sender: AnyObject) {
#if SHOWCASE
		updateCache()
#else
		AppDelegate.shared.togglePeering()
#endif
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
		peerVC.peerID = table[cellPath.section][cellPath.row].0
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		(try? BrowseFilter.getFilter()).map { filter = $0 }

		tabBarController?.tabBar.items?[AppDelegate.BrowseTabBarIndex].badgeValue = nil

		networkButton.layer.cornerRadius = networkButton.bounds.height / 2.0
		networkButton.tintColor = AppTheme.tintColor
		if #available(iOS 13, *) {
			// WHAT THE FUCK WHY DOES IT NOT WORK: networkButton.backgroundColor = AppTheme.backgroundColor
			networkButton.backgroundColor = self.traitCollection.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
		} else {
			networkButton.backgroundColor = UIColor.white
		}

		connectionChangedState(viewModel.peering)
		observeNotifications()
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)

		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		if #available(iOS 13, *) {
			// WHAT THE FUCK WHY DOES IT NOT WORK: networkButton.backgroundColor = AppTheme.backgroundColor
			networkButton.backgroundColor = self.traitCollection.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
		}
	}

	// MARK: UITableViewDataSource
	
	override func numberOfSections(in tableView: UITableView) -> Int {
		return placeholderCellActive ? 1 : (filter.displayFilteredPeople ? table.count : 1)
	}
	
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return placeholderCellActive ? 1 : table[section].count
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

#if SHOWCASE
			cell.setContent(mode: .alone)
#else
			cell.setContent(mode: viewModel.peering ? .alone : .offline)
#endif

			return cell
		}

		guard let cell = tableView.dequeueReusableCell(withIdentifier: BrowseViewController.PeerDisplayCellID) as? PeerTableViewCell else {
			assertionFailure("well that didn't work out so well2")
			return UITableViewCell()
		}

		let peerID = table[indexPath.section][indexPath.row].0
		let model = viewModel.viewModel(of: peerID)
		cell.fill(with: model, PeereeIdentityViewModelController.viewModel(of: peerID))

		// load the picture of the peer from disk once it is displayed
		if model.picture == nil && model.info.hasPicture {
			PeeringController.shared.loadPortraitFromDisk(of: peerID)
		}

		return cell
	}
	
	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		guard !placeholderCellActive, table[section].count > 0, let peerSection = TableSection(rawValue: section) else {
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
		return table[section].firstIndex { $0.0 == peerID }
	}

	private func indexPath(of peerID: PeerID) -> IndexPath? {
		for i in 0..<table.count  {
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

		return trailingSwipeActionsConfigurationFor(peerID: table[indexPath.section][indexPath.row].0)
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

	/// Adds `peerID` to `table` and returns the appropriate section.
	private func addToTable(_ peerID: PeerID) -> Int {
		let model = viewModel.viewModel(of: peerID)
		let pinState = PeereeIdentityViewModelController.viewModel(of: peerID).pinState
		let section: TableSection = filter.check(info: model.info, pinState: pinState) ? .inFilter : .outFilter
		table[section.rawValue].insert((model.peerID, model.lastSeen), at: 0)
		return section.rawValue
	}

	/// Adds `peerID` to `table` and updates `tableView`.
	private func addToView(_ peerID: PeerID, updateTable: Bool) {
		_ = addToTable(peerID)
		if updateTable { tableView.reloadData() }
		// this sometimes crashed, when peerAppeared occured when we are offline:
/*
		let placeHolderWasActive = placeholderCellActive
		let section = addToTable(peerID)

		if updateTable {
			if placeHolderWasActive {
				tableView.reloadData()
			} else {
				add(row: 0, section: section)
			}
		}
 */
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
		addToView(peerID, updateTable: true)
	}
	
	private func peerDisappeared(_ peerID: PeerID) {
		reload(peerID: peerID)
	}
	
	private func connectionChangedState(_ nowOnline: Bool) {
		tableView.reloadData()

#if SHOWCASE
		networkButton.setTitle(NSLocalizedString("Go Offline", comment: "Toggle to offline mode. Also title in browse view."), for: [])
#else
		if nowOnline {
			networkButton.setTitle(NSLocalizedString("Go Offline", comment: "Toggle to offline mode. Also title in browse view."), for: [])
			updateCache()
		} else {
			networkButton.setTitle(NSLocalizedString("Go Online", comment: "Toggle to online mode. Also title in browse view."), for: [])

			clearViewCache()
			tableView.reloadData()
		}
#endif

		networkButton.setNeedsLayout()
		tableView.isScrollEnabled = nowOnline
	}

	/// Moves a peer within (!) its current section to the appropriate position, based on its `lastSeen` value.
	private func reload(peerID: PeerID) {
		guard let indexPath = indexPath(of: peerID), let oldSection = TableSection(rawValue: indexPath.section) else { return }

		let newModel = viewModel.viewModel(of: peerID)
		if newModel.lastSeen == table[indexPath.section][indexPath.row].1 {
			tableView.reloadRows(at: [indexPath], with: .automatic)
		} else {
			var newIndexPath = position(in: oldSection, lastSeen: newModel.lastSeen)
			// we assume that only the lastSeen attribute changed and nothing that affects the filter (s.t. the section keeps the same)
			let immediatelyAfterOrSameRange = indexPath.row...indexPath.row+1
			if immediatelyAfterOrSameRange.contains(newIndexPath.row) {
				tableView.reloadRows(at: [indexPath], with: .automatic)
			} else {
				if newIndexPath.row > indexPath.row {
					newIndexPath.row -= 1
				}
				table[indexPath.section].remove(at: indexPath.row)
				table[indexPath.section].insert((newModel.peerID, newModel.lastSeen), at: newIndexPath.row)
				tableView.moveRow(at: indexPath, to: newIndexPath)
				tableView.reloadRows(at: [newIndexPath], with: .automatic)
			}
		}
	}

	/// Calculates the position of a peer in the lastSeen-sorted section.
	private func position(in section: TableSection, lastSeen: Date) -> IndexPath {
		// We assume our table is sorted by lastSeen already. We could even do a binary search here.
		let row = table[section.rawValue].firstIndex { (_, lastLastSeen) in
			return lastSeen > lastLastSeen
		}
		return IndexPath(row: row ?? 0, section: section.rawValue)
	}

	/// Populates `viewCache` from scratch.
	private func updateCache() {
#if SHOWCASE
		let displayedModels = PeerViewModelController.viewModels.values
#else
		let now = Date()
		let cal = Calendar.current as NSCalendar
		let userPeerID = PeereeIdentityViewModelController.userPeerID

		var displayedModels = viewModel.viewModels.values.filter { model in
			let lastSeenAgoCalc = cal.components(NSCalendar.Unit.hour, from: model.lastSeen, to: now, options: []).hour
			let lastSeenAgo = lastSeenAgoCalc ?? BrowseViewController.MaxRememberedHours + 1
			return lastSeenAgo < BrowseViewController.MaxRememberedHours && model.peerID != userPeerID
		}
		displayedModels.sort { a, b in a.lastSeen > b.lastSeen }
#endif

		clearViewCache()
		for displayedModel in displayedModels {
			let pinState = PeereeIdentityViewModelController.viewModel(of: displayedModel.peerID).pinState
			let section: TableSection = filter.check(info: displayedModel.info, pinState: pinState) ? .inFilter : .outFilter
			table[section.rawValue].append((displayedModel.peerID, displayedModel.lastSeen))
		}
		self.tableView?.reloadData()
	}

	/// Removes all entries from the subarrays of `viewCache`.
	private func clearViewCache() {
		for i in 0..<table.count { table[i].removeAll() }
	}

	private func observeNotifications() {
		notificationObservers.append(PeeringController.Notifications.peerAppeared.addAnyPeerObserver { [weak self] (peerID, notification) in
			let again = notification.userInfo?[PeeringController.NotificationInfoKey.again.rawValue] as? Bool
			self?.peerAppeared(peerID, again: again ?? false)
		})
		notificationObservers.append(PeeringController.Notifications.peerDisappeared.addAnyPeerObserver { [weak self] (peerID, _) in self?.peerDisappeared(peerID) })
		notificationObservers.append(PeeringController.Notifications.connectionChangedState.addObserver { [weak self] notification in
			self?.connectionChangedState((notification.userInfo?[PeeringController.NotificationInfoKey.connectionState.rawValue] as? NSNumber)?.boolValue ?? PeerViewModelController.shared.peering)
		})
		notificationObservers.append(PeeringController.Notifications.persistedPeersLoadedFromDisk.addObserver { [weak self] _ in
			self?.updateCache()
		})
		notificationObservers.append(PeereeIdentityViewModel.NotificationName.pinStateUpdated.addObserver { [weak self] _ in
			self?.updateCache()
		})

		let reloadBlock: (PeerID, Notification) -> Void = { [weak self] (peerID, _) in self?.reload(peerID: peerID) }
		notificationObservers.append(PeerViewModel.NotificationName.pictureLoaded.addAnyPeerObserver(reloadBlock))

		notificationObservers.append(BrowseFilter.NotificationName.filterChanged.addObserver { [weak self] notification in
			guard let strongSelf = self else { return }

			if let newFilter = notification.object as? BrowseFilter {
				strongSelf.filter = newFilter
			}
			strongSelf.updateCache()
		})
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

			if #available(iOS 11.0, *) {
				guard ProcessInfo.processInfo.thermalState != .critical else {
					vibrancyEffectView.effect = nil
					blurEffectView.effect = nil
					return
				}
			}

			let blurEffect: UIBlurEffect
			if #available(iOS 13.0, *) {
				subheadLabel.textColor = UIColor.label
				blurEffect = UIBlurEffect(style: .systemThinMaterial)
			} else {
				subheadLabel.textColor = UIColor.black
				blurEffect = UIBlurEffect(style: .extraLight)
			}
			blurEffectView.effect = blurEffect
			vibrancyEffectView.effect = UIVibrancyEffect(blurEffect: blurEffect)

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
			if PeerViewModelController.shared.isBluetoothOn {
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
