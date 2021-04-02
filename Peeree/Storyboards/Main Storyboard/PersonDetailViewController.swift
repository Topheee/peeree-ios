//
//  PersonDetailViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class PersonDetailViewController: UIViewController, ProgressManagerDelegate, UITextViewDelegate {
	@IBOutlet private weak var portraitImageView: ProgressImageView!
	@IBOutlet private weak var portraitEffectView: RoundedVisualEffectView!
	@IBOutlet private weak var ageLabel: UILabel!
	@IBOutlet private weak var genderLabel: UILabel!
	@IBOutlet private weak var verificationStatusLabel: UILabel!
	@IBOutlet private weak var verificationImage: UIImageView!
	@IBOutlet private weak var pinButton: UIButton!
	@IBOutlet private weak var traitsButton: UIButton!
	@IBOutlet private weak var gradientView: GradientView!
	@IBOutlet private weak var pinIndicator: UIActivityIndicatorView!
	@IBOutlet private weak var findButtonItem: UIBarButtonItem!
	@IBOutlet private weak var peerStackView: UIStackView!
	@IBOutlet private weak var propertyStackView: UIStackView!
	@IBOutlet private weak var peerIDLabel: UILabel!
	
	// Button for executing the message send.
	@IBOutlet private weak var sendMessageButton: UIButton!
	@IBOutlet private weak var messageTableHeight: NSLayoutConstraint!
	@IBOutlet private weak var chatTableViewContainer: UIView!
	@IBOutlet private weak var messageBar: UIView!
	// Text field used for typing text messages to send to peers
	@IBOutlet private weak var messageTextView: UITextView!
	@IBOutlet private weak var messageBottomConstraint: NSLayoutConstraint!
	
	private static let unwindSegueID = "unwindToBrowseViewController"
	static let storyboardID = "PersonDetailViewController"
	static let beaconSegueID = "beaconSegue"
	
	private var chatTableView: UITableView? { return chatTableViewContainer.subviews.first as? UITableView }
	
	private var timer: Timer?
	
	private var notificationObservers: [NSObjectProtocol] = []
	
	private var pictureProgressManager: ProgressManager?
	
	/// caches
	private var cachedState = PeerState()
	private var displayedPeerInfo: PeerInfo?
	var peerManager: PeerManager!
	
	@IBAction func reportPeer(_ sender: Any) {
		guard let manager = self.peerManager, let peer = manager.peerInfo else { return }
		let alertController = UIAlertController(title: NSLocalizedString("Report or Unpin", comment: "Title of alert"), message: NSLocalizedString("Mark the content of this user as inappropriate or unpin them to no longer receive messages.", comment: "Message of alert"), preferredStyle: UIAlertController.Style.alert)
		alertController.preferredAction = alertController.addCancelAction()
		let unpinAction = UIAlertAction(title: NSLocalizedString("Unpin", comment: "Alert action button title"), style: .default) { (action) in
			AccountController.shared.unpin(peer: peer)
		}
		unpinAction.isEnabled = !manager.isLocalPeer && peer.pinned
		alertController.addAction(unpinAction)
		let reportAction = UIAlertAction(title: NSLocalizedString("Report Portrait", comment: "Alert action button title"), style: .destructive) { (action) in
			AccountController.shared.report(manager: manager) { (error) in
				AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Reporting Portrait Failed", comment: "Title of alert dialog"))
			}
		}
		reportAction.isEnabled = !manager.isLocalPeer && peer.hasPicture && manager.cgPicture != nil && manager.pictureClassification == .none
		alertController.addAction(reportAction)
		
		alertController.present()
	}
	
	// Action method when user presses "send"
	@IBAction func sendMessageTapped(sender: Any) {
		guard let message = messageTextView.text, message != "" else { return }
		
		self.messageTextView.text = ""
		
		self.sendMessageButton.isEnabled = false
		peerManager.send(message: message) { error in
			if let error = error {
				AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Sending Message Failed", comment: "Title of alert dialog"))
			}
		}
	}
	
	@IBAction func unwindToBrowseViewController(_ segue: UIStoryboardSegue) {}
	
	@IBAction func pinPeer(_ sender: UIButton) {
		guard let peer = displayedPeerInfo else { return }
		guard !peer.pinned else {
			AccountController.shared.updatePinStatus(of: peer)
			return
		}
		
		AppDelegate.requestPin(of: peer)
		updateState()
	}
	
	@IBAction func tapImage(_ sender: Any) {
		if messageTextView.isFirstResponder {
			// provide more space for the chat
			messageTextView.resignFirstResponder()
			portraitImageView.setNeedsLayout()
		} else {
			// show greater picture
			layoutMetadata(isHorizontal: false)
		}
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let charTraitVC = segue.destination as? CharacterTraitViewController {
			charTraitVC.characterTraits = displayedPeerInfo?.characterTraits
			charTraitVC.userTraits = false
		} else if let beaconVC = segue.destination as? BeaconViewController {
			beaconVC.peerManager = peerManager
		} else if let messageViewController = segue.destination as? MessageTableViewController {
			messageViewController.peerManager = peerManager
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		for view in propertyStackView.arrangedSubviews {
			view.layer.backgroundColor = AppTheme.tintColor.cgColor
			view.layer.cornerRadius = view.layer.bounds.height / 2.0
		}
		pinButton.setImage(#imageLiteral(resourceName: "PinButtonTemplatePressed"), for: [.disabled, .selected])
		messageBar.layer.borderWidth = 0.5
		messageBar.layer.borderColor = UIColor.lightGray.cgColor
		messageTextView.layer.cornerRadius = 15.0
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		// make sure that we always have the latest PeerInfo here, because, e.g. when coming back from Find View the portrait may have been loaded meanwhile and as we have value semantics this change is not populated to our displayedPeerInfo variable
		if peerManager != nil {
			displayedPeerInfo = peerManager.peerInfo ?? displayedPeerInfo
		}
		
		updateState()
		
		let simpleStateUpdate = { [weak self] (notification: Notification) in
			guard let peerID = notification.userInfo?[PeeringController.NotificationInfoKey.peerID.rawValue] as? PeerID, let strongSelf = self else { return }
			guard strongSelf.displayedPeerInfo?.peerID == peerID else { return }
			// as we have value semantics, our cached peer info does not change, so we have to get the updated one
			strongSelf.displayedPeerInfo = strongSelf.peerManager.peerInfo ?? strongSelf.displayedPeerInfo
			strongSelf.updateState()
		}
		
		notificationObservers.append(PeeringController.Notifications.peerAppeared.addObserver(usingBlock: simpleStateUpdate))
		notificationObservers.append(PeeringController.Notifications.peerDisappeared.addObserver(usingBlock: simpleStateUpdate))
		notificationObservers.append(PeerManager.Notifications.verified.addObserver(usingBlock: simpleStateUpdate))
		
		let simpleHandledNotifications2: [AccountController.Notifications] = [.pinned, .pinningStarted, .pinFailed, .unpinFailed, .pinStateUpdated, .peerReported]
		for networkNotification in simpleHandledNotifications2 {
			notificationObservers.append(networkNotification.addObserver(usingBlock: simpleStateUpdate))
		}
		
		notificationObservers.append(AccountController.Notifications.pinMatch.addObserver(usingBlock: { [weak self] (notification) in
			simpleStateUpdate(notification)
			self?.gradientView?.animateGradient = true
		}))

		notificationObservers.append(AccountController.Notifications.unpinned.addObserver(usingBlock: { [weak self] (notification) in
			simpleStateUpdate(notification)
			self?.messageTextView?.resignFirstResponder()
		}))
		
		registerForKeyboardNotifications()
		
		// somehow sometimes it is still hidden from BrowseViewController
		navigationController?.setNavigationBarHidden(false, animated: false)
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		guard let peer = displayedPeerInfo else { return }
		
		let progress = peerManager.loadPicture()
		portraitImageView.loadProgress = progress
		progress.map { pictureProgressManager = ProgressManager(progress: $0, delegate: self, queue: DispatchQueue.main) }
		gradientView.animateGradient = peer.pinMatched
		
		if peer.pinMatched {
			messageTextView.becomeFirstResponder()
			chatTableView?.scrollToBottom(animated: true)
		}
		
		// somehow the animation does not work directly when viewDidAppear is called for the first time, probably because AppDelegate instantiates it via code
		guard !UIAccessibility.isReduceMotionEnabled && peer.pinned else { return }
		timer = Timer.scheduledTimer(timeInterval: peer.pinned ? 0.5 : 5.0, target: self, selector: #selector(animatePinButton(timer:)), userInfo: nil, repeats: false)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		NotificationCenter.default.removeObserver(self)
		for observer in notificationObservers { NotificationCenter.`default`.removeObserver(observer) }
		notificationObservers.removeAll()
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		pictureProgressManager = nil
		gradientView.animateGradient = false
		portraitImageView.loadProgress = nil
		portraitImageView.image = nil
		
		// reset position from animation, if the user slides back in
		timer?.invalidate()
		timer = nil
		pinButton.layer.removeAllAnimations()
		
		// reverse toolbar modifications, otherwise the toolbar disappears when going into Radar view and back
		messageTextView.resignFirstResponder()
		messageTableHeight.isActive = false
	}
	
	// MARK: UITextFieldDelegate methods
	
	// Dynamically enables/disables the send button based on user typing
	func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
		let length = (textView.text?.count ?? 0) - range.length + text.count;
		self.sendMessageButton.isEnabled = length > 0
		return true
	}
	
	// MARK: ProgressDelegate
	
	func progressDidPause(_ progress: Progress) {
		// ignored
	}
	
	func progressDidCancel(_ progress: Progress) {
		if progress === pictureProgressManager?.progress {
			pictureProgressManager = nil
		}
	}
	
	func progressDidResume(_ progress: Progress) {
		// ignored
	}
	
	func progressDidUpdate(_ progress: Progress) {
		if progress === pictureProgressManager?.progress {
			if progress.completedUnitCount == progress.totalUnitCount {
				pictureProgressManager = nil
				// as we have value semantics, our cached peer info does not change, so we have to get the updated one
				displayedPeerInfo = peerManager.peerInfo
				updateState()
			}
		}
	}

	// MARK: Private methods
	
	private func updateState() {
		guard let peer = displayedPeerInfo, let state = peerManager else { return }

		cachedState.isAvailable = state.isAvailable
		messageBar.isHidden = !peer.pinMatched || state.isLocalPeer
		if messageBar.isHidden { messageBar.resignFirstResponder() }
		pinButton.isHidden = state.pinState == .pinning || peerStackView.axis == .horizontal
		pinButton.isEnabled = !state.isLocalPeer
		pinButton.isSelected = state.pinState == .pinned
//		traitsButton.isHidden = state.peerInfoDownloadState != .downloaded
		pinIndicator.isHidden = state.pinState != .pinning || peerStackView.axis == .horizontal
		findButtonItem.isEnabled = peer.pinMatched
		sendMessageButton.isEnabled = messageTextView.text?.count ?? 0 > 0
		peerIDLabel.text = peer.peerID.uuidString
		
		title = peer.nickname
		if state.isLocalPeer || cachedState.isAvailable {
			navigationItem.titleView = nil
			navigationItem.title = peer.nickname
			pinButton.layer.removeAllAnimations()
		} else {
			let titleLable = UILabel(frame: CGRect(x:0, y:0, width: 200, height: 45))
			titleLable.text = peer.nickname
			titleLable.textColor = UIColor.lightGray
			titleLable.textAlignment = .center
			titleLable.lineBreakMode = .byTruncatingTail
			navigationItem.titleView = titleLable
		}
		
		ageLabel.text = peer.age.map { (theAge) -> String in "\(theAge)" }
		ageLabel.isHidden = peer.age == nil
		genderLabel.text = peer.gender.localizedRawValue
		verificationStatusLabel.text = state.verificationStatus
		verificationImage.isHighlighted = state.verified
		verificationImage.tintColor = state.verified ? UIColor.green : UIColor.red
		switch state.pictureClassification {
			case .none:
				portraitImageView.image = state.picture ?? (peer.hasPicture ? #imageLiteral(resourceName: "PortraitPlaceholder") : #imageLiteral(resourceName: "PortraitUnavailable"))
				portraitEffectView.effect = nil
			case .pending:
				portraitImageView.image = state.picture ?? (peer.hasPicture ? #imageLiteral(resourceName: "PortraitPlaceholder") : #imageLiteral(resourceName: "PortraitUnavailable"))
				portraitEffectView.effect = UIBlurEffect(style: UIBlurEffect.Style.dark)
			case .objectionable:
				portraitImageView.image = #imageLiteral(resourceName: "ObjectionablePortraitPlaceholder")
				portraitEffectView.effect = nil
		}
		if #available(iOS 11.0, *) {
			portraitImageView.accessibilityIgnoresInvertColors = state.picture != nil
		}
	}
	
	// TODO merge with WelcomeViewController.animatePinButton()
	@objc private func animatePinButton(timer: Timer?) {
		guard let peer = displayedPeerInfo else { return }
		UIView.animate(withDuration: 1.0, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 1.0, options: peer.pinned ? [] : [.autoreverse, .repeat, .allowUserInteraction], animations: {
			self.pinButton.frame = self.pinButton.frame.offsetBy(dx: 0.0, dy: -3.0)
		}, completion: nil)
		self.timer = nil
	}
	
	private func registerForKeyboardNotifications() {
		// TODO UIResponder.keyboardDidChangeFrameNotification / keyboardWillChangeFrameNotification
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
	}
	
	/// Called when the UIKeyboardWillShowNotification is sent.
	@objc private func keyboardWillShow(notification: Notification) {
		let animationDuration = notification.userInfo![UIResponder.keyboardAnimationDurationUserInfoKey] as! NSNumber
		self.layoutMetadata(isHorizontal: true, animationDuration: animationDuration.doubleValue)
		// move the toolbar frame up as keyboard animates into view
		self.moveToolBar(up: true, for: notification)
	}
	
	/// Called when the UIKeyboardWillHideNotification is sent
	@objc private func keyboardWillHide(notification: Notification) {
		// move the toolbar frame down as keyboard animates into view
		self.moveToolBar(up: false, for: notification)
	}
	
	// pragma mark - Toolbar animation helpers
	
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

		messageBottomConstraint.constant = -1.0 + (up ? keyboardFrame.size.height - inset : 0.0)
		UIView.animateAlongKeyboard(notification: keyboardNotification, animations: {
			self.view.layoutIfNeeded()
		}, completion: nil)
		messageTableHeight.isActive = up
		if up {
			chatTableView?.scrollToBottom(animated: true)
		}
	}
	
	private func layoutMetadata(isHorizontal: Bool, animationDuration: TimeInterval = 0.25) {
		guard self.peerStackView.axis == (isHorizontal ? .vertical : .horizontal) else { return /* nothing changed */ }

		// the pin button needs to be hidden at the beginning of animation
		self.pinButton.isHidden = isHorizontal
		self.pinIndicator.isHidden = true
		UIView.animate(withDuration: animationDuration, animations: { () -> Void in
			self.peerStackView.axis = isHorizontal ? .horizontal : .vertical
			self.propertyStackView.axis = isHorizontal ? .vertical : .horizontal
			self.propertyStackView.alignment = isHorizontal ? .leading : .center
			self.chatTableViewContainer.isHidden = !isHorizontal
			self.peerIDLabel.isHidden = isHorizontal
		}, completion: nil)
	}
}

fileprivate struct PeerState {
	var isAvailable = false
}
