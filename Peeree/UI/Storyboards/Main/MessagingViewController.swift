//
//  MessagingViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.04.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import UIKit
import PeereeCore
import PeereeServerChat
import PeereeDiscovery

class MessagingViewController: PeerViewController, UITextViewDelegate {
	// Button for executing the message send.
	@IBOutlet private weak var sendMessageButton: UIButton!
	@IBOutlet private weak var chatTableViewContainer: UIView!
	// Text field used for typing text messages to send to peers
	@IBOutlet private weak var messageTextView: UITextView!
	@IBOutlet private weak var messageBottomConstraint: NSLayoutConstraint!
	@IBOutlet private weak var portraitImageButton: UIButton!

	private var notificationObservers: [NSObjectProtocol] = []

	private var isFirstTimeOpened = true

	private var chatTableView: UITableView? { return chatTableViewContainer.subviews.first as? UITableView }

	// Action method when user presses "send"
	@IBAction func sendMessageTapped(sender: Any) {
		guard let message = messageTextView.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), message != "" else { return }

		self.messageTextView.text = ""

		self.sendMessageButton.isEnabled = false
		let title = NSLocalizedString("Sending Message Failed", comment: "Title of alert dialog")
		ServerChatFactory.getOrSetupInstance { instanceResult in
			switch instanceResult {
			case .failure(let error):
				InAppNotificationController.display(serverChatError: error, localizedTitle: title)
			case .success(let serverChat):
				serverChat.send(message: message, to: self.peerID) { result in
					result.mError.map { InAppNotificationController.display(serverChatError: $0, localizedTitle: title) }
				}
			}
		}
	}
	
	private func setPortraitButtonImage() {
		portraitImageButton.setImage(model.createRoundedPicture(cropRect: portraitImageButton.bounds, backgroundColor: navigationController?.navigationBar.barTintColor ?? AppTheme.tintColor), for: .normal)
		// background color of navigationController?.navigationBar.barTintColor ?? AppTheme.tintColor does not work (at least) on iPhone SE 2 (it has a different color than the bar)
		// so we need to use cornerRadius
		portraitImageButton.layer.cornerRadius = portraitImageButton.bounds.height / 2.0
		portraitImageButton.layer.masksToBounds = true
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		portraitImageButton.layer.cornerRadius = portraitImageButton.bounds.height / 2.0
		portraitImageButton.layer.masksToBounds = true
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		if #available(iOS 14, *) {
			// SF-Symbols work
		} else {
			sendMessageButton.setTitle(NSLocalizedString("Send", comment: "Message Button Title"), for: .normal)
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		setPortraitButtonImage()
		navigationItem.prompt = model.info.nickname
		observeNotifications()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

#if SHOWCASE
#else
		guard idModel.pinState == .pinMatch else {
			unwind()
			return
		}
#endif

		registerForKeyboardNotifications()
		messageTextView.isEditable = false

		ServerChatFactory.getOrSetupInstance { instanceResult in
			let title = NSLocalizedString("Chat Unavailable", comment: "Title of alert dialog")

			switch instanceResult {
			case .failure(let error):
				InAppNotificationController.display(serverChatError: error, localizedTitle: title)

			case .success(let serverChat):
				serverChat.canChat(with: self.peerID) { error in
					error.map { InAppNotificationController.display(serverChatError: $0, localizedTitle: title) }
					guard error == nil else { return }

					serverChat.markAllMessagesRead(of: self.peerID)

					DispatchQueue.main.async {
						self.messageTextView.isEditable = true
						self.messageTextView.becomeFirstResponder()
					}
				}
			}
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		messageTextView?.resignFirstResponder()

		ServerChatFactory.getOrSetupInstance { instanceResult in
			instanceResult.value?.markAllMessagesRead(of: self.peerID)
		}
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)

		NotificationCenter.default.removeObserver(self)
		for observer in notificationObservers { NotificationCenter.`default`.removeObserver(observer) }
		notificationObservers.removeAll()
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		(segue.destination as? PeerObserverContainer)?.peerID = peerID
	}

	// MARK: UITextFieldDelegate methods

	// Dynamically enables/disables the send button based on user typing
	func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
		let length = (textView.text?.count ?? 0) - range.length + text.count;
		self.sendMessageButton.isEnabled = length > 0
		return true
	}

	private func registerForKeyboardNotifications() {
		// TODO UIResponder.keyboardDidChangeFrameNotification / keyboardWillChangeFrameNotification
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
	}

	/// Called when the UIKeyboardWillShowNotification is sent.
	@objc private func keyboardWillShow(notification: Notification) {
		// move the toolbar frame up as keyboard animates into view
		self.moveToolBar(up: true, for: notification)
	}

	/// Called when the UIKeyboardWillHideNotification is sent
	@objc private func keyboardWillHide(notification: Notification) {
		// move the toolbar frame down as keyboard animates into view
		self.moveToolBar(up: false, for: notification)
	}

	// MARK: - Toolbar animation helpers

	// Helper method for moving the toolbar frame based on user action
	private func moveToolBar(up: Bool, for keyboardNotification: Notification) {
		guard let userInfo = keyboardNotification.userInfo else { return }
		
		let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! CGRect
		let inset: CGFloat
		if #available(iOS 11.0, *) {
			inset = view.safeAreaInsets.bottom
		} else {
			inset = 0.0
		}

		messageBottomConstraint.constant = up ? keyboardFrame.size.height - inset : 0.0
		UIView.animateAlongKeyboard(notification: keyboardNotification) {
			self.view.layoutIfNeeded()
		}

		if up {
			chatTableView?.scrollToBottom(animated: !isFirstTimeOpened)
			isFirstTimeOpened = false
		}
	}

	/// Observes relevant notifications in `NotificationCenter`.
	private func observeNotifications() {
		notificationObservers.append(PeerViewModel.NotificationName.pictureLoaded.addPeerObserver(for: peerID) { [weak self] _ in
			self?.setPortraitButtonImage()
		})
		notificationObservers.append(AccountController.NotificationName.unpinned.addPeerObserver(for: peerID) { [weak self] _ in
			self?.unwind()
		})
		notificationObservers.append(AccountController.NotificationName.unmatch.addPeerObserver(for: peerID) { [weak self] _ in
			self?.unwind()
		})
		notificationObservers.append(ServerChatNotificationName.readyToChat.addPeerObserver(for: peerID) { [weak self] _ in
			self?.messageTextView?.isEditable = true
			self?.messageTextView?.becomeFirstResponder()
		})
		notificationObservers.append(UIApplication.willResignActiveNotification.addObserver { [weak self] _ in
			guard let strongSelf = self else { return }

			ServerChatFactory.getOrSetupInstance { instanceResult in
				instanceResult.value?.markAllMessagesRead(of: strongSelf.peerID)
			}
		})
	}

	/// Unwind us from the view hierarchy.
	private func unwind() {
		performSegue(withIdentifier: "unwindToPinMatchTableViewController", sender: nil)
	}
}
