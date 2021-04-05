//
//  PersonDetailViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class PersonDetailViewController: PeerViewController, ProgressManagerDelegate, UITextViewDelegate {
	@IBOutlet private weak var portraitImageView: ProgressImageView!
	@IBOutlet private weak var portraitEffectView: RoundedVisualEffectView!
	@IBOutlet private weak var ageLabel: UILabel!
	@IBOutlet private weak var genderLabel: UILabel!
	@IBOutlet private weak var pinButton: UIButton!
	@IBOutlet private weak var traitsButton: UIButton!
	@IBOutlet private weak var gradientView: GradientView!
	@IBOutlet private weak var pinIndicator: UIActivityIndicatorView!
	@IBOutlet private weak var findButtonItem: UIBarButtonItem!
	@IBOutlet private weak var peerIDLabel: UILabel!
	@IBOutlet private weak var bioTextView: UITextView!
	@IBOutlet private weak var reportButton: UIBarButtonItem!
	
	@IBOutlet private weak var ageTagView: RoundedRectView!
	// label constraints
	@IBOutlet private weak var genderLabelTop: NSLayoutConstraint!
	@IBOutlet private weak var genderLabelLeading: NSLayoutConstraint!
	@IBOutlet private weak var ageLabelTrailing: NSLayoutConstraint!
	@IBOutlet private weak var ageLabelBottom: NSLayoutConstraint!

	private static let unwindSegueID = "unwindToBrowseViewController"
	static let storyboardID = "PersonDetailViewController"
	static let beaconSegueID = "beaconSegue"
	
	private var timer: Timer?
	
	private var notificationObservers: [NSObjectProtocol] = []
	
	private var pictureProgressManager: ProgressManager?
	private var bioProgressManager: ProgressManager?

	/// caches
	private var displayedPeerInfo: PeerInfo?
	
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

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let beaconVC = segue.destination as? BeaconViewController {
			beaconVC.peerManager = peerManager
		} else if let charTraitVC = segue.destination as? CharacterTraitViewController {
			charTraitVC.characterTraits = displayedPeerInfo?.characterTraits
			charTraitVC.userTraits = false
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		pinButton.setImage(#imageLiteral(resourceName: "PinButtonTemplatePressed"), for: [.disabled, .selected])
		if #available(iOS 14, *) {
			// SF-Symbols work
		} else {
			reportButton.title = NSLocalizedString("Report", comment: "Report Bar Button Title")
		}
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
		
		let simpleHandledNotifications2: [AccountController.Notifications] = [.pinned, .pinningStarted, .pinFailed, .unpinFailed, .pinStateUpdated, .peerReported]
		for networkNotification in simpleHandledNotifications2 {
			notificationObservers.append(networkNotification.addObserver(usingBlock: simpleStateUpdate))
		}
		
		notificationObservers.append(AccountController.Notifications.pinMatch.addObserver(usingBlock: { [weak self] (notification) in
			simpleStateUpdate(notification)
			self?.gradientView?.animateGradient = true
		}))

		notificationObservers.append(AccountController.Notifications.unpinned.addObserver(usingBlock: { (notification) in
			simpleStateUpdate(notification)
		}))
		
		UIView.animate(withDuration: 2.0) {
			// 0.707106781186548 = sin(45°)
			let r = (self.portraitImageView.bounds.width + 16.0) / 2.0
			let edgeDistance = r - 0.707106781186548 * r
			self.genderLabelTop.constant = edgeDistance
			self.genderLabelLeading.constant = edgeDistance - self.genderLabel.bounds.width / 2.0
			self.ageLabelBottom?.constant = edgeDistance
			self.ageLabelTrailing?.constant = edgeDistance - self.ageLabel.bounds.width / 2.0
		}
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		guard let peer = displayedPeerInfo else { return }
		
		let (pictureProgress, bioProgress) = peerManager.loadResources()
		portraitImageView.loadProgress = pictureProgress
		pictureProgress.map { pictureProgressManager = ProgressManager(progress: $0, delegate: self, queue: DispatchQueue.main) }
		bioProgress.map { bioProgressManager = ProgressManager(progress: $0, delegate: self, queue: DispatchQueue.main) }
		gradientView.animateGradient = peer.pinMatched

		// somehow the animation does not work directly when viewDidAppear is called for the first time, probably because AppDelegate instantiates it via code
		guard !UIAccessibility.isReduceMotionEnabled && peer.pinned else { return }
		timer = Timer.scheduledTimer(timeInterval: peer.pinned ? 0.5 : 5.0, target: self, selector: #selector(animatePinButton(timer:)), userInfo: nil, repeats: false)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
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
	}

	// MARK: ProgressDelegate
	
	func progressDidPause(_ progress: Progress) {
		// ignored
	}
	
	func progressDidCancel(_ progress: Progress) {
		if progress === pictureProgressManager?.progress {
			pictureProgressManager = nil
		} else if progress === pictureProgressManager?.progress {
			bioProgressManager = nil
		}
	}
	
	func progressDidResume(_ progress: Progress) {
		// ignored
	}
	
	func progressDidUpdate(_ progress: Progress) {
		if progress.completedUnitCount == progress.totalUnitCount {
			if progress === pictureProgressManager?.progress {
				pictureProgressManager = nil
			} else if progress === bioProgressManager?.progress {
				bioProgressManager = nil
			}
			// as we have value semantics, our cached peer info does not change, so we have to get the updated one
			displayedPeerInfo = peerManager.peerInfo
			updateState()
		}
	}

	// MARK: Private methods
	
	private func updateState() {
		guard let peer = displayedPeerInfo, let state = peerManager else { return }

		pinButton.isHidden = state.pinState == .pinning
		pinButton.isEnabled = !state.isLocalPeer
		pinButton.isSelected = state.pinState == .pinned
		pinIndicator.isHidden = state.pinState != .pinning
		findButtonItem.isEnabled = peer.pinMatched
		peerIDLabel.text = peer.peerID.uuidString
		bioTextView.text = peer.biography

		title = peer.nickname
		if state.isLocalPeer || state.isAvailable {
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
		ageTagView.isHidden = peer.age == nil
		genderLabel.text = peer.gender.localizedRawValue
		if #available(iOS 13.0, *) {
			portraitImageView.layer.shadowColor = peer.pinMatched ? AppTheme.tintColor.cgColor : UIColor.systemBackground.cgColor
		} else {
			portraitImageView.layer.shadowColor = peer.pinMatched ? AppTheme.tintColor.cgColor : UIColor.black.cgColor
		}
		portraitImageView.layer.shadowPath = UIBezierPath(ovalIn: portraitImageView.layer.bounds).cgPath
		portraitImageView.layer.shadowOpacity = 0.8
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
}
