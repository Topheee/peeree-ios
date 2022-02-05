//
//  MessageTableViewController.swift
//  Peeree
//  Based on the MainViewController from the MultiPeerGroupChat example project
//
//  Created by Christopher Kobusch on 08.05.19.
//  Copyright © 2019 Kobusch. All rights reserved.
//

import UIKit

class MessageTableViewController: PeerTableViewController, PeerMessagingObserver {
	private var lastCount = 0
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		peerObserver.messagingObserver = self
		tableView.keyboardDismissMode = .interactive
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		tableView.reloadData()
		modifyModel { model in model.unreadMessages = 0 }
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
		lastCount = model.transcripts.count
		return lastCount
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		guard let cell = tableView.dequeueReusableCell(withIdentifier: "Message Cell", for: indexPath) as? MessageCell else {
			assertionFailure("well that didn't message out so well")
			return UITableViewCell()
		}

		cell.set(transcript: model.transcripts[indexPath.row])
		return cell
	}

	// MARK: - PeerMessagingObserver

	func messageQueued() {
		modifyModel { model in model.unreadMessages = 0 }
		appendTranscript()
	}

	func messageReceived() {
		modifyModel { model in model.unreadMessages = 0 }
		appendTranscript()
	}
	func messageSent() { appendTranscript() }
	func unreadMessageCountChanged() { /* ignored */ }

	// MARK: - Private Methods
	
	// Helper method for inserting a sent/received message into the data source and reload the view.
	// Make sure you call this on the main thread
	private func appendTranscript() {
		self.tableView.reloadData()

		// Scroll to the bottom so we focus on the latest message
		self.tableView.scrollToBottom(animated: true)
	}

}
