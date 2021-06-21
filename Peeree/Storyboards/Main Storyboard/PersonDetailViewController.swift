//
//  PersonDetailViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class PersonDetailViewController: PeerViewController, ProgressManagerDelegate, UITextViewDelegate {
	@IBOutlet private weak var picturePinStackView: UIStackView!
	@IBOutlet private weak var portraitImageView: ProgressImageView!
	@IBOutlet private weak var portraitEffectView: RoundedVisualEffectView!
	@IBOutlet private weak var ageLabel: UILabel!
	@IBOutlet private weak var genderLabel: UILabel!
	@IBOutlet private weak var pinButton: UIButton!
	@IBOutlet private weak var pinCircleView: CircleView!
	@IBOutlet private weak var traitsButton: UIButton!
	@IBOutlet private weak var gradientView: GradientView!
	@IBOutlet private weak var pinIndicator: UIActivityIndicatorView!
	@IBOutlet private weak var findButtonItem: UIBarButtonItem!
	@IBOutlet private weak var peerIDLabel: UILabel!
	@IBOutlet private weak var bioTextView: UITextView!
	@IBOutlet private weak var bioHeadingLabel: UILabel!
	@IBOutlet private weak var reportButton: UIBarButtonItem!
	@IBOutlet private weak var signatureLabel: UILabel!
	
	@IBOutlet private weak var portraitContainer: UIView!
	@IBOutlet private weak var ageTagView: RoundedRectView!
	@IBOutlet private weak var genderTagView: RoundedRectView!

	@IBOutlet private weak var pinStackView: UIStackView!

	// outer label constraints - strong reference as we may deactivate them, which would destroy them
	@IBOutlet private var genderLabelTop: NSLayoutConstraint!
	@IBOutlet private var genderLabelLeading: NSLayoutConstraint!
	@IBOutlet private var ageLabelTrailing: NSLayoutConstraint!
	@IBOutlet private var ageLabelBottom: NSLayoutConstraint!

	// inner label constraints
	@IBOutlet private weak var ageStackLeading: NSLayoutConstraint!
	@IBOutlet private weak var ageStackTrailing: NSLayoutConstraint!
	@IBOutlet private weak var genderStackLeading: NSLayoutConstraint!
	@IBOutlet private weak var genderStackTrailing: NSLayoutConstraint!

	//pin constraints
	@IBOutlet private weak var pinToCircleTop: NSLayoutConstraint!
	@IBOutlet private weak var pinToCircleLeading: NSLayoutConstraint!
	@IBOutlet private weak var pinToCircleBottom: NSLayoutConstraint!
	@IBOutlet private weak var pinToCircleTrailing: NSLayoutConstraint!

	@IBOutlet private weak var signatureToBioConstraint: NSLayoutConstraint!

	private var compactLabelStackView: UIStackView? = nil

	private static let unwindSegueID = "unwindToBrowseViewController"
	static let storyboardID = "PersonDetailViewController"
	static let beaconSegueID = "beaconSegue"

	private var notificationObservers: [NSObjectProtocol] = []
	
	private var pictureProgressManager: ProgressManager?
	private var bioProgressManager: ProgressManager?

	/// caches
	private var displayedPeerInfo: PeerInfo?
	
	@IBAction func reportPeer(_ sender: Any) {
		guard let manager = self.peerManager, let peer = displayedPeerInfo else { return }
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

	@IBAction func tapBiography(_ sender: Any) {
		let wasCompact = picturePinStackView.axis == .horizontal
		let oldBackgroundColor = pinCircleView.backgroundColor
		let hideBioContent = hideBioContent(for: wasCompact ? .vertical : .horizontal)
		pinCircleView.backgroundColor = nil
		pinCircleView.isOpaque = false
		bioTextView.isHidden = false
		signatureLabel.isHidden = false
		peerIDLabel.isHidden = hideBioContent
		pinStackView.isHidden = pinButton.isSelected && wasCompact

		UIView.animate(withDuration: 0.30, delay: 0.0, options: [.curveEaseInOut]) { [self] in
			signatureLabel.alpha = hideBioContent ? 0.0 : 1.0
		} completion: { [self] (completed) in
			signatureLabel.isHidden = hideBioContent
		}

		let mainAnimationDuration = 0.45
		UIView.animate(withDuration: mainAnimationDuration, delay: 0.0, options: [.curveEaseInOut]) { [self] in
			picturePinStackView.axis = wasCompact ? .vertical : .horizontal
			picturePinStackView.alignment = wasCompact ? .center : .fill

			signatureToBioConstraint.constant = wasCompact ? -50.0 : 8.0
			bioTextView.alpha = hideBioContent ? 0.0 : 1.0

			let circleInset: CGFloat = wasCompact ? 5.0 : 26.0
			let constraintInset = circleInset + 3.0
			pinToCircleTop.constant = constraintInset
			pinToCircleLeading.constant = constraintInset
			pinToCircleTrailing.constant = constraintInset
			pinToCircleBottom.constant = constraintInset
			pinCircleView.circleInsets = UIEdgeInsets(top: circleInset, left: circleInset, bottom: circleInset, right: circleInset)

			compactLabelStackView?.removeFromSuperview()

			// tie tag circle to anchored side (TODO make this whole thing leading/trailing aware)
			if let genderStackView = genderTagView.subviews.first as? UIStackView {
				if !wasCompact {
					if let label = genderStackView.arrangedSubviews.first as? UILabel {
						genderStackView.removeArrangedSubview(label)
						genderStackView.addArrangedSubview(label)
					}
				} else if let circle = genderStackView.arrangedSubviews.first as? CircleView {
					genderStackView.removeArrangedSubview(circle)
					genderStackView.addArrangedSubview(circle)
				}
				genderStackLeading.constant = wasCompact ? 8.0 : 2.0
				genderStackTrailing.constant = wasCompact ? 2.0 : 8.0
			}
			if !wasCompact {
				let tagStackView = UIStackView(arrangedSubviews: [UIView(frame: CGRect.zero), genderTagView, ageTagView, UIView(frame: CGRect.zero)])
				tagStackView.axis = .vertical
				tagStackView.alignment = .leading
				tagStackView.distribution = .equalSpacing
				tagStackView.spacing = 12.0
				compactLabelStackView = tagStackView
				pinStackView.insertArrangedSubview(tagStackView, at: 0)
			} else {
				portraitContainer.addSubview(genderTagView)
				portraitContainer.addSubview(ageTagView)
			}
			genderLabelTop.isActive = wasCompact
			genderLabelLeading.isActive = wasCompact
			ageLabelTrailing.isActive = wasCompact
			ageLabelBottom.isActive = wasCompact
		} completion: { [self] (_) in
			pinCircleView.isOpaque = true
			pinCircleView.backgroundColor = oldBackgroundColor
			bioTextView.isHidden = hideBioContent
			bioTextView.superview?.setNeedsDisplay()
			// reset animation because frame size changed
			animatePinButton()
			updatePinCircleWidth()
		}
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let beaconVC = segue.destination as? BeaconViewController {
			beaconVC.peerManager = peerManager
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
		if let manager = peerManager {
			displayedPeerInfo = manager.peerInfo ?? PinMatchesController.shared.peerInfo(for: manager.peerID) ?? displayedPeerInfo
		}
		
		updateState()
		
		let simpleStateUpdate = { [weak self] (notification: Notification) in
			guard let peerID = notification.userInfo?[PeeringController.NotificationInfoKey.peerID.rawValue] as? PeerID,
				  let strongSelf = self, let manager = strongSelf.peerManager else { return }
			guard manager.peerID == peerID else { return }
			// as we have value semantics, our cached peer info does not change, so we have to get the updated one
			strongSelf.displayedPeerInfo = manager.peerInfo ?? PinMatchesController.shared.peerInfo(for: manager.peerID) ?? strongSelf.displayedPeerInfo
			strongSelf.updateState()
			strongSelf.animatePinButton()
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

		notificationObservers.append(AccountController.Notifications.pinMatch.addObserver(usingBlock: { [weak self] (notification) in
			simpleStateUpdate(notification)
			self?.gradientView?.animateGradient = true
		}))

		notificationObservers.append(AccountController.Notifications.unpinned.addObserver(usingBlock: { (notification) in
			simpleStateUpdate(notification)
		}))
		
		// 0.707106781186548 = sin(45°)
		let r = (self.portraitImageView.bounds.width + 16.0) / 2.0
		let edgeDistance = r - 0.707106781186548 * r
		self.genderLabelTop.constant = edgeDistance
		self.genderLabelLeading.constant = edgeDistance - self.genderLabel.bounds.width / 2.0
		self.ageLabelBottom?.constant = edgeDistance
		self.ageLabelTrailing?.constant = edgeDistance - self.ageLabel.bounds.width / 2.0
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		guard let peer = displayedPeerInfo else { return }
		
		let (pictureProgress, bioProgress) = peerManager.loadResources()
		portraitImageView.loadProgress = pictureProgress
		pictureProgress.map { pictureProgressManager = ProgressManager(progress: $0, delegate: self, queue: DispatchQueue.main) }
		bioProgress.map { bioProgressManager = ProgressManager(progress: $0, delegate: self, queue: DispatchQueue.main) }
		gradientView.animateGradient = peer.pinMatched

		animatePinButton()
		updatePinCircleWidth()
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
		clearPinAnimations()
	}

	func clearPinAnimations() {
		pinCircleView?.layer.removeAllAnimations()
		pinButton?.layer.removeAllAnimations()
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

	private func hideOrShowPinRelatedViews() {
		let headerCompact = picturePinStackView.axis == .horizontal
		// we use pinButton.isSelected instead of peerManager.pinState here, so that we do not depend on the peerManager
		let pinned = pinButton.isSelected
		let hideBioContent = hideBioContent(for: picturePinStackView.axis)

		pinStackView.isHidden = pinned && !headerCompact
		bioTextView.isHidden = hideBioContent
		peerIDLabel.isHidden = hideBioContent
		signatureLabel.isHidden = hideBioContent
	}

	private func hideBioContent(for axis: NSLayoutConstraint.Axis) -> Bool {
		return !(axis == .horizontal || pinButton.isSelected)
	}

	private func updateState() {
		guard let peer = displayedPeerInfo, let state = peerManager else { return }

		updatePinCircleWidth()
		pinButton.isHidden = state.pinState == .pinning
		pinButton.isEnabled = !state.isLocalPeer
		pinButton.isSelected = state.pinState == .pinned
		pinIndicator.isHidden = state.pinState != .pinning
		findButtonItem.isEnabled = peer.pinMatched
		peerIDLabel.text = peer.peerID.uuidString
		bioTextView.text = peer.biography
		hideOrShowPinRelatedViews()

		title = peer.nickname
		if state.isLocalPeer || state.isAvailable {
			navigationItem.titleView = nil
			navigationItem.title = peer.nickname
		} else {
			let titleLable = UILabel(frame: CGRect(x:0, y:0, width: 200, height: 45))
			titleLable.text = peer.nickname
			titleLable.textColor = UIColor.lightGray
			titleLable.textAlignment = .center
			titleLable.lineBreakMode = .byTruncatingTail
			navigationItem.titleView = titleLable
		}

		signatureLabel.text = peer.nickname
		ageLabel.text = peer.age.map { (theAge) -> String in "\(theAge)" }
		ageTagView.isHidden = peer.age == nil
		genderLabel.text = peer.gender.localizedRawValue
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

	private func updatePinCircleWidth() {
		pinCircleView.strokeWidth = pinCircleView.bounds.width * 0.03
	}

	// TODO merge with WelcomeViewController.animatePinButton()
	private func animatePinButton() {
		clearPinAnimations()
		guard peerManager.pinState != .pinned else { return }

		if let pinView = pinButton, let circleView = pinCircleView, !UIAccessibility.isReduceMotionEnabled {
			UIView.animate(withDuration: 1.2, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 1.0, options: [.autoreverse, .allowUserInteraction, .repeat, .curveEaseInOut]) {
				// how much the circle is scaled down
				let scaleFactor: CGFloat = -0.05
				let circleFrame = circleView.frame
				pinView.frame = pinView.frame.offsetBy(dx: -circleFrame.width * scaleFactor, dy: 0.0)
				circleView.frame = circleView.frame.insetBy(dx: circleFrame.width * scaleFactor, dy: circleFrame.height * scaleFactor)
			} completion: { (completed) in
				// ignored
			}
		}
	}
}
