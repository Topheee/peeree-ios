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
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		notificationObservers.append(PeerManager.Notifications.messageReceived.addPeerObserver(for: peerManager.peerID) { [weak self] _ in
			self?.peerManager.unreadMessages = 0
			self?.appendTranscript()
		})
		
		notificationObservers.append(PeerManager.Notifications.messageSent.addPeerObserver(for: peerManager.peerID) { [weak self] _ in
			self?.appendTranscript()
		})
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		peerManager.unreadMessages = 0
	}
	
	deinit {
		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
		}
	}
	
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        lastCount = peerManager?.transcripts.count ?? 0
		return lastCount
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		// Get the transcript for this row
		let transcript = peerManager.transcripts[indexPath.row]
		
		guard let cell = tableView.dequeueReusableCell(withIdentifier: "Message Cell", for: indexPath) as? MessageCell else {
			assertionFailure("well that didn't message out so well")
			return UITableViewCell()
		}
		cell.set(transcript: transcript)
		return cell
    }

	// pragma mark - private methods
	
	// Helper method for inserting a sent/received message into the data source and reload the view.
	// Make sure you call this on the main thread
	func appendTranscript() {
		// Update the table view
		let newIndexPath = IndexPath(row:(peerManager.transcripts.count - 1), section: 0)
		self.tableView.insertRows(at: [newIndexPath], with: .fade)
		
		// Scroll to the bottom so we focus on the latest message
		let numberOfRows = self.tableView.numberOfRows(inSection: 0)
		if (numberOfRows > 0) {
			self.tableView.scrollToRow(at: IndexPath(row:(numberOfRows - 1), section: 0), at: .bottom, animated: true)
		}
	}

}
