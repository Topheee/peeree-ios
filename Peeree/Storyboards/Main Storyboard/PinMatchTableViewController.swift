//
//  PinMatchTableViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 23.05.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import UIKit

class PinMatchTableViewController: UITableViewController {
	private static let MatchedPeerCellID = "matchedPeerCell"
	private static let PlaceholderPeerCellID = "placeholderCell"
	private static let AddAnimation = UITableView.RowAnimation.automatic
	private static let DelAnimation = UITableView.RowAnimation.automatic

	static let MessagePeerSegueID = "MessagePeerSegue"

	private var peerCache: [PeerInfo] = []
	private var managerCache: [PeerManager] = []

	private var placeholderCellActive: Bool {
		return peerCache.count == 0 || !PeeringController.shared.peering
	}

	private var notificationObservers: [NSObjectProtocol] = []

	private func updateCache(isInitial: Bool = false) {
		PinMatchesController.shared.persistence.read { newPeerCache in
			guard !(isInitial && newPeerCache.count == 0) else { return }

			PeeringController.shared.managers(for: newPeerCache.map { $0.peerID }) { peerManagers in
				peerManagers.forEach { $0.loadLocalPicture {_ in } }
				DispatchQueue.main.async {
					self.peerCache = Array(newPeerCache)
					self.managerCache = peerManagers
					self.tableView?.reloadData()
				}
			}
		}
	}

	private func listenForNotifications() {
		for notificationType: PeerManager.Notifications in [.unreadMessageCountChanged, .messageReceived, .messageSent] {
			notificationObservers.append(notificationType.addPeerObserver { [weak self] peerID, _  in
				self?.messageReceivedSentOrRead(from: peerID)
			})
		}

		let reloadBlock: (PeerID, Notification) -> Void = { [weak self] (peerID, _) in self?.reload(peerID: peerID) }
		notificationObservers.append(PeerManager.Notifications.pictureLoaded.addPeerObserver(usingBlock: reloadBlock))
		notificationObservers.append(AccountController.Notifications.pinMatch.addPeerObserver { [weak self] peerID, _ in
			self?.addToView(peerID: peerID, updateTable: true)
		})
		notificationObservers.append(AccountController.Notifications.unpinned.addPeerObserver { [weak self] peerID, _ in
			guard let strongSelf = self,
				  let peerPath = strongSelf.indexPath(of: peerID) else {
				return
			}

			strongSelf.peerCache.remove(at: peerPath.row)
			strongSelf.managerCache.remove(at: peerPath.row)
		})
		notificationObservers.append(AccountController.Notifications.accountCreated.addObserver { [weak self] _ in
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
		notificationObservers.append(PinMatchesController.Notifications.pinMatchedPeersUpdated.addObserver { [weak self] _ in
			self?.updateCache()
		})
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		updateCache(isInitial: true)
		listenForNotifications()
		tableView.scrollsToTop = true
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
		peerVC.peerID = managerCache[cellPath.row].peerID
	}

	deinit {
		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	// MARK: UITableViewDataSource

	override func numberOfSections(in tableView: UITableView) -> Int { return 1 }
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		tableView.isScrollEnabled = !placeholderCellActive
		return placeholderCellActive ? 1 : peerCache.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if placeholderCellActive {
			let cell = tableView.dequeueReusableCell(withIdentifier: PinMatchTableViewController.PlaceholderPeerCellID) as! PlaceHolderTableViewCell
			if PeeringController.shared.peering {
				let accountExists = AccountController.shared.accountExists
				cell.heading = accountExists ? NSLocalizedString("No Pin Matches Yet", comment: "Heading of placeholder cell in Pin Matches view.") : NSLocalizedString("Missing Peeree Identity", comment: "Heading of placeholder cell in Pin Matches view.")
				cell.subhead = accountExists ? NSLocalizedString("Go online and pin new people!", comment: "Subhead of placeholder cell in Pin Matches view.") : NSLocalizedString("Create an identity in your profile.", comment: "Subhead of placeholder cell in Pin Matches view.")
			} else {
				cell.heading = NSLocalizedString("Offline Mode", comment: "Heading of the offline mode placeholder shown in browse view.")
				cell.subhead = NSLocalizedString("Go online and pin new people!", comment: "Subhead of placeholder cell in Pin Matches view.")
			}
			return cell
		} else {
			let cell = tableView.dequeueReusableCell(withIdentifier: PinMatchTableViewController.MatchedPeerCellID)!
			fill(cell: cell, peer: peerCache[indexPath.row], manager: managerCache[indexPath.row])
			return cell
		}
	}

	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		if #available(iOS 11.0, *) {
			return !placeholderCellActive ? super.tableView(tableView, heightForRowAt: indexPath) : tableView.bounds.height - tableView.adjustedContentInset.bottom
		} else {
			return !placeholderCellActive ? super.tableView(tableView, heightForRowAt: indexPath) : tableView.bounds.height - tableView.contentInset.bottom
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

	private func fill(cell: UITableViewCell, peer: PeerInfo, manager: PeerManager) {
		cell.textLabel?.highlightedTextColor = AppTheme.tintColor
		cell.textLabel?.text = peer.nickname
		let unreadMessages = manager.unreadMessages
		let format = NSLocalizedString("%u messages.", comment: "")
		let unreadMessageCountText = String(format: format, unreadMessages)
		if unreadMessages > 0 {
			cell.detailTextLabel?.text = "\(manager.unreadMessages) 📫\t\(manager.transcripts.last?.message ?? unreadMessageCountText)"
		} else {
			cell.detailTextLabel?.text = "📭\t\(manager.transcripts.last?.message ?? unreadMessageCountText)"
		}
		guard let imageView = cell.imageView else { assertionFailure(); return }
		imageView.image = manager.pictureClassification == .none ? manager.picture ?? (peer.hasPicture ? #imageLiteral(resourceName: "PortraitPlaceholder") : #imageLiteral(resourceName: "PortraitUnavailable")) : #imageLiteral(resourceName: "ObjectionablePortraitPlaceholder")
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

	private func messageReceivedSentOrRead(from peerID: PeerID) {
		guard let peerPath = indexPath(of: peerID) else {
			NSLog("WARN: Received message from non-displayed peer \(peerID.uuidString).")
			return
		}
		let topIndexPath = IndexPath(row: 0, section: 0)
		if peerPath.row != 0 {
			peerCache.swapAt(0, peerPath.row)
			managerCache.swapAt(0, peerPath.row)
			tableView.moveRow(at: peerPath, to: topIndexPath)
		}
		tableView.reloadRows(at: [topIndexPath], with: .automatic)
	}

	private func reload(peerID: PeerID) {
		guard let indexPath = indexPath(of: peerID) else { return }

		tableView.reloadRows(at: [indexPath], with: .automatic)
	}

	private func add(row: Int) {
		tableView.insertRows(at: [IndexPath(row: row, section: 0)], with: PinMatchTableViewController.AddAnimation)
	}

	private func indexPath(of peerID: PeerID) -> IndexPath? {
		if let row = peerCache.firstIndex(where: { $0.peerID == peerID }) {
			return IndexPath(row: row, section: 0)
		}
		return nil
	}

	private func addToCache(peer: PeerInfo, manager: PeerManager) {
		peerCache.insert(peer, at: 0)
		managerCache.insert(manager, at: 0)
	}

	private func addToView(peerID: PeerID, updateTable: Bool) {
		let manager = PeeringController.shared.manager(for: peerID)
		guard let peer = manager.peerInfo else {
			assertionFailure()
			return
		}

		let placeHolderWasActive = placeholderCellActive
		addToCache(peer: peer, manager: manager)

		if updateTable {
			if placeHolderWasActive {
				tableView.reloadData()
			} else {
				add(row: 0)
			}
		}
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
