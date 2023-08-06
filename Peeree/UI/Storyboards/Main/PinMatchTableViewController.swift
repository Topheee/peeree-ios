//
//  PinMatchTableViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 23.05.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import UIKit
import PeereeCore
import PeereeServer
import PeereeServerChat
import PeereeDiscovery

/// Displays list of pin matched peers and the last messages in their conversations.
final class PinMatchTableViewController: UITableViewController {
	private static let MatchedPeerCellID = "matchedPeerCell"
	private static let PlaceholderPeerCellID = "placeholderCell"
	private static let AddAnimation = UITableView.RowAnimation.automatic
	private static let DelAnimation = UITableView.RowAnimation.automatic

	static let MessagePeerSegueID = "MessagePeerSegue"

	@IBAction func unwindToPinMatchTableViewController(_ segue: UIStoryboardSegue) { }

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.scrollsToTop = true
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		tabBarController?.tabBar.items?[AppDelegate.PinMatchesTabBarIndex].badgeValue = nil

		updateCache()
		observeNotifications()
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
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
		peerVC.peerID = table[cellPath.row]
	}

	// MARK: UITableViewDataSource

	override func numberOfSections(in tableView: UITableView) -> Int { return 1 }
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		tableView.isScrollEnabled = !placeholderCellActive
		return placeholderCellActive ? 1 : table.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if placeholderCellActive {
			let cell = tableView.dequeueReusableCell(withIdentifier: PinMatchTableViewController.PlaceholderPeerCellID) as! PlaceHolderTableViewCell
			if PeereeIdentityViewModelController.accountExists {
				cell.heading = NSLocalizedString("No Pin Matches Yet", comment: "Heading of placeholder cell in Pin Matches view.")
				cell.subhead = NSLocalizedString("Go online and pin new people!", comment: "Subhead of placeholder cell in Pin Matches view.")
			} else {
				cell.heading = NSLocalizedString("Missing Peeree Identity", comment: "Heading of placeholder cell in Pin Matches view.")
				cell.subhead = NSLocalizedString("Create an identity in your profile.", comment: "Subhead of placeholder cell in Pin Matches view.")
				let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapPlaceholderCell(_:)))
				cell.addGestureRecognizer(gestureRecognizer)
			}
			return cell
		} else {
			let cell = tableView.dequeueReusableCell(withIdentifier: PinMatchTableViewController.MatchedPeerCellID)!
			fill(cell: cell, model: PeerViewModelController.shared.viewModel(of: table[indexPath.row]), chatModel: ServerChatViewModelController.shared.viewModel(of: table[indexPath.row]))
			return cell
		}
	}

	@objc func tapPlaceholderCell(_ sender: Any) {
		if PeereeIdentityViewModelController.accountExists {
			AppDelegate.shared.togglePeering()
		} else {
			AppDelegate.presentOnboarding()
		}
	}

	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		if #available(iOS 11.0, *) {
			return !placeholderCellActive ? super.tableView(tableView, heightForRowAt: indexPath) : tableView.bounds.height - tableView.adjustedContentInset.bottom
		} else {
			return !placeholderCellActive ? super.tableView(tableView, heightForRowAt: indexPath) : tableView.bounds.height - tableView.contentInset.bottom
		}
	}

	// MARK: UITableViewDelegate

	@available(iOS 11.0, *)
	override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		guard !placeholderCellActive else { return nil }

		return trailingSwipeActionsConfigurationFor(peerID: table[indexPath.row])
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

	// MARK: - Private

	// MARK: Variables

	/// Data source for `tableView`.
	private var table: [PeerID] = []

	/// Whether `tableView` should display only one cell containing a status info.
	private var placeholderCellActive: Bool {
		return table.count == 0
	}

	/// Reference holder to `NotificationCenter` observers.
	private var notificationObservers: [NSObjectProtocol] = []

	// MARK: Methods

	/// Populates `table` from scratch.
	private func updateCache() {
#if SHOWCASE
		table = PeerViewModelController.viewModels.values.map { $0.peerID }
#else
		var pinMatchedPeerViewModels: [(peerID: PeerID, lastMessage: Date?, lastSeen: Date)] = PeereeIdentityViewModelController.viewModels.values.compactMap { idModel in
			guard idModel.pinState == .pinMatch else { return nil }
			let lastSeen = PeerViewModelController.shared.viewModels[idModel.peerID]?.lastSeen ?? Date()
			let chatModel = ServerChatViewModelController.shared.viewModels[idModel.peerID]
			return (idModel.peerID, chatModel?.lastMessage?.timestamp, lastSeen)
		}

		pinMatchedPeerViewModels.sort { a, b in
			guard let aTimestamp = a.lastMessage else {
				if b.lastMessage == nil {
					return a.lastSeen > b.lastSeen
				} else {
					return false
				}
			}

			guard let bTimestamp = b.lastMessage else {
				return true
			}

			return aTimestamp > bTimestamp
		}

		table = pinMatchedPeerViewModels.map { $0.peerID }
#endif

		self.tableView?.reloadData()
	}

	private func fill(cell: UITableViewCell, model: PeerViewModel, chatModel: ServerChatViewModel) {
		cell.textLabel?.highlightedTextColor = AppTheme.tintColor
		cell.textLabel?.text = model.info.nickname
		let unreadMessages = chatModel.unreadMessages
		let format = NSLocalizedString("%u messages.", comment: "")
		let unreadMessageCountText = String(format: format, unreadMessages)
		if unreadMessages > 0 {
			cell.detailTextLabel?.text = "📫 (\(chatModel.unreadMessages)) \(chatModel.lastMessage?.message ?? unreadMessageCountText)"
		} else {
			cell.detailTextLabel?.text = "📭 \(chatModel.lastMessage?.message ?? unreadMessageCountText)"
		}
		guard let imageView = cell.imageView else { assertionFailure(); return }
		imageView.image = model.portraitOrPlaceholder
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
			imageView.accessibilityIgnoresInvertColors = model.picture != nil
		}

		// load the picture of the peer from disk once it is displayed
		if model.picture == nil && model.info.hasPicture {
			PeeringController.shared.loadPortraitFromDisk(of: model.peerID)
		}
	}

	private func messageReceivedSentOrRead(from peerID: PeerID) {
		guard let peerPath = indexPath(of: peerID) else {
			wlog("Received message from non-displayed peer \(peerID.uuidString).")
			return
		}

		let topIndexPath = IndexPath(row: 0, section: 0)
		if peerPath.row != 0 {
			table.swapAt(0, peerPath.row)
			tableView.moveRow(at: peerPath, to: topIndexPath)
			tableView.reloadRows(at: [topIndexPath, peerPath], with: .automatic)
		} else {
			tableView.reloadRows(at: [topIndexPath], with: .automatic)
		}
	}

	private func reload(peerID: PeerID) {
		guard let indexPath = indexPath(of: peerID) else { return }

		tableView.reloadRows(at: [indexPath], with: .automatic)
	}

	private func add(row: Int) {
		tableView.insertRows(at: [IndexPath(row: row, section: 0)], with: PinMatchTableViewController.AddAnimation)
	}

	private func indexPath(of peerID: PeerID) -> IndexPath? {
		if let row = table.firstIndex(where: { $0 == peerID }) {
			return IndexPath(row: row, section: 0)
		}
		return nil
	}

	private func addToCache(_ peerID: PeerID) {
		table.insert(peerID, at: 0)
	}

	private func addToView(peerID: PeerID, updateTable: Bool) {
		//let placeHolderWasActive = placeholderCellActive
		addToCache(peerID)

		if updateTable { tableView.reloadData() }
		/* this would be the performant variant, however I saw crashes with it (the number of rows after insert …), probably due to placeholderCellActive changing in between, because PeeringController.shared.peering is a data race
		if updateTable {
			if placeHolderWasActive {
				tableView.reloadData()
			} else {
				add(row: 0)
			}
		}
		 */
	}

	/// Observes relevant notifications in `NotificationCenter`.
	private func observeNotifications() {
		for notificationType: ServerChatViewModel.NotificationName in [.unreadMessageCountChanged, .messageReceived, .messageSent] {
			notificationObservers.append(notificationType.addAnyPeerObserver { [weak self] peerID, _  in
				self?.messageReceivedSentOrRead(from: peerID)
			})
		}

		notificationObservers.append(PeerViewModel.NotificationName.pictureLoaded.addAnyPeerObserver { [weak self] (peerID, _) in self?.reload(peerID: peerID) })
		notificationObservers.append(AccountController.NotificationName.pinMatch.addAnyPeerObserver { [weak self] peerID, _ in
			self?.addToView(peerID: peerID, updateTable: true)
		})
		notificationObservers.append(AccountController.NotificationName.unpinned.addAnyPeerObserver { [weak self] peerID, _ in
			guard let strongSelf = self,
				  let peerPath = strongSelf.indexPath(of: peerID) else {
				return
			}

			strongSelf.table.remove(at: peerPath.row)
		})
		notificationObservers.append(AccountController.NotificationName.accountCreated.addObserver { [weak self] _ in
			self?.tableView.reloadData()
		})
		notificationObservers.append(PeeringController.Notifications.connectionChangedState.addObserver { [weak self] notification in
			guard let state = notification.userInfo?[PeeringController.NotificationInfoKey.connectionState.rawValue] as? NSNumber,
				  let strongSelf = self else { return }
			if state.boolValue {
				strongSelf.updateCache()
			} else {
				strongSelf.tableView.reloadData()
			}
		})
		notificationObservers.append(PeeringController.Notifications.persistedPeersLoadedFromDisk.addObserver { [weak self] _ in
			self?.updateCache()
		})
	}
}

final class PlaceHolderTableViewCell: UITableViewCell {
	@IBOutlet private weak var headLabel: UILabel!
	@IBOutlet private weak var subheadLabel: UILabel!

	var heading: String {
		get { return headLabel?.text ?? "" }
		set { headLabel?.text = newValue }
	}

	var subhead: String {
		get { return subheadLabel?.text ?? "" }
		set { subheadLabel?.text = newValue }
	}
}
