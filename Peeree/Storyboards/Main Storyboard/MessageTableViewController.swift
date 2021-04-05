//
//  MessageTableViewController.swift
//  Peeree
//  Based on the MainViewController from the MultiPeerGroupChat example project
//
//  Created by Christopher Kobusch on 08.05.19.
//  Copyright © 2019 Kobusch. All rights reserved.
//

import UIKit

class MessageTableViewController: UITableViewController {
	var peerManager: PeerManager!
	
	private var lastCount = 0
	
	private var notificationObservers: [NSObjectProtocol] = []

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		notificationObservers.append(PeerManager.Notifications.messageReceived.addPeerObserver(for: peerManager.peerID) { [weak self] _ in
			self?.peerManager.unreadMessages = 0
			self?.appendTranscript()
		})
		
		notificationObservers.append(PeerManager.Notifications.messageSent.addPeerObserver(for: peerManager.peerID) { [weak self] _ in
			self?.appendTranscript()
		})

		notificationObservers.append(PeerManager.Notifications.messageQueued.addPeerObserver(for: peerManager.peerID) { [weak self] _ in
			self?.appendTranscript()
		})
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		peerManager.unreadMessages = 0
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
		}
		notificationObservers.removeAll()
	}
	
	// MARK: - Table view data source

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if let manager = peerManager {
			lastCount = manager.transcripts.count + manager.pendingMessages.count
		} else {
			lastCount = 0
		}
		return lastCount
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		guard let manager = peerManager,
			  let cell = tableView.dequeueReusableCell(withIdentifier: "Message Cell", for: indexPath) as? MessageCell else {
			assertionFailure("well that didn't message out so well")
			return UITableViewCell()
		}

		// Get the transcript for this row
		let overflow = indexPath.row - manager.transcripts.count
		let transcript: Transcript
		if overflow < 0 {
			transcript = manager.transcripts[indexPath.row]
		} else {
			transcript = Transcript(direction: .send, message: manager.pendingMessages[overflow].message)
		}
		cell.set(transcript: transcript, pending: overflow >= 0)
		return cell
	}

	// pragma mark - private methods
	
	// Helper method for inserting a sent/received message into the data source and reload the view.
	// Make sure you call this on the main thread
	private func appendTranscript() {
		self.tableView.reloadData()

		// Scroll to the bottom so we focus on the latest message
		self.tableView.scrollToBottom(animated: true)
	}

}
