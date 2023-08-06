//
//  MessageTableViewController.swift
//  Peeree
//  Based on the MainViewController from the MultiPeerGroupChat example project
//
//  Created by Christopher Kobusch on 08.05.19.
//  Copyright © 2019 Kobusch. All rights reserved.
//

import UIKit

import PeereeCore
import PeereeServerChat

class MessageTableViewController: PeerTableViewController, PeerMessagingObserver {
	override func viewDidLoad() {
		super.viewDidLoad()

		headerDateFormatter.timeStyle = .none
		headerDateFormatter.dateStyle = .full
	}

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
		return chatModel.transcriptDays.count
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
#if SHOWCASE
		return 2
#else
		return chatModel.transcripts[chatModel.transcriptDays[section]]?.count ?? 0
#endif
	}

	private let headerDateFormatter = DateFormatter()

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		let day = chatModel.transcriptDays[section]
		return headerDateFormatter.string(from: Calendar.current.date(from: day.dateComponents) ?? Date())
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		guard let transcript = self.chatModel.transcript(at: indexPath) else {
			assertionFailure("well that didn't message out so well")
			return UITableViewCell()
		}

		let cell = tableView.dequeueReusableCell(withIdentifier: transcript.direction == .send ? "SendMessageCell" : "ReceiveMessageCell", for: indexPath)

#if SHOWCASE
		switch indexPath.row {
		case 0:
			(cell as? MessageCell)?.set(transcript: Transcript(direction: .send, message: NSLocalizedString("Hey, I really like your moves! Wanna take a break together at the bar?", comment: "Showcase text message"), timestamp: Date()))
		default:
			(cell as? MessageCell)?.set(transcript: Transcript(direction: .receive, message: NSLocalizedString("Sure, meet me there!", comment: "Showcase text message"), timestamp: Date()))
		}
#else
		(cell as? MessageCell)?.set(transcript: transcript)
#endif
		return cell
	}

	// MARK: UITableViewDelegate

	override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
		let text = self.chatModel.transcript(at: indexPath)?.message ?? ""
		return text.height(forConstrainedWidth: tableView.bounds.width, font: messageFont)
	}

	override func scrollViewDidScroll(_ scrollView: UIScrollView) {
		guard scrollView.contentOffset == CGPointZero else { return }

		ServerChatFactory.chat { $0?.fetchMessagesFromStore(peerID: self.peerID, count: 20) }
	}

	// MARK: - PeerMessagingObserver

	func messageQueued() {
		appendTranscript()
	}

	func messageReceived() {
		appendTranscript()
	}
	func messageSent() { appendTranscript() }
	func unreadMessageCountChanged() { appendTranscript(scroll: false) }

	private let messageFont = UIFont.preferredFont(forTextStyle: .body)

	// MARK: - Private Methods
	
	// Helper method for inserting a sent/received message into the data source and reload the view.
	// Make sure you call this on the main thread
	private func appendTranscript(scroll: Bool = true) {
		markRead()
		self.tableView.reloadData()

		// Scroll to the bottom so we focus on the latest message
		if scroll { self.tableView.scrollToBottom(animated: true) }
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
