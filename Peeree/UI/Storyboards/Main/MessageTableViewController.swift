//
//  MessageTableViewController.swift
//  Peeree
//  Based on the MainViewController from the MultiPeerGroupChat example project
//
//  Created by Christopher Kobusch on 08.05.19.
//  Copyright © 2019 Kobusch. All rights reserved.
//

import UIKit
import PeereeServerChat

class MessageTableViewController: PeerTableViewController, PeerMessagingObserver {
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		peerObserver.messagingObserver = self
		tableView.keyboardDismissMode = .interactive
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		tableView.reloadData()
		markRead()
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		peerObserver.messagingObserver = nil
	}
	
	// MARK: - Table view data source

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
#if SHOWCASE
		return 2
#else
		return chatModel.transcripts.count
#endif
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		guard let cell = tableView.dequeueReusableCell(withIdentifier: "Message Cell", for: indexPath) as? MessageCell else {
			assertionFailure("well that didn't message out so well")
			return UITableViewCell()
		}

#if SHOWCASE
		switch indexPath.row {
		case 0:
			cell.set(transcript: Transcript(direction: .send, message: NSLocalizedString("Hey, I really like your moves! Wanna take a break together at the bar?", comment: "Showcase text message"), timestamp: Date()))
		default:
			cell.set(transcript: Transcript(direction: .receive, message: NSLocalizedString("Sure, meet me there!", comment: "Showcase text message"), timestamp: Date()))
		}
#else
		cell.set(transcript: chatModel.transcripts[indexPath.row])
#endif
		return cell
	}

	// MARK: - PeerMessagingObserver

	func messageQueued() {
		appendTranscript()
	}

	func messageReceived() {
		appendTranscript()
	}
	func messageSent() { appendTranscript() }
	func unreadMessageCountChanged() { /* ignored */ }

	// MARK: - Private Methods
	
	// Helper method for inserting a sent/received message into the data source and reload the view.
	// Make sure you call this on the main thread
	private func appendTranscript() {
		markRead()
		self.tableView.reloadData()

		// Scroll to the bottom so we focus on the latest message
		self.tableView.scrollToBottom(animated: true)
	}

	/// Declare all messages in this thread as being read.
	private func markRead() {
		ServerChatViewModelController.shared.modify(peerID: peerID) { serverChatModel in
			serverChatModel.unreadMessages = 0
		}

		let peerID = self.peerID
		ServerChatFactory.chat { sc in
			sc?.set(lastRead: Date(), of: peerID)
		}
	}
}
