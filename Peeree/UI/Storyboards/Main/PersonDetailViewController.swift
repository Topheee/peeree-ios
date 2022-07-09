//
//  PersonDetailViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class PersonDetailViewController: PeerViewController, ProgressManagerDelegate, UITextViewDelegate {
	private static let bioAnimationDuration: TimeInterval = 0.45
	private static let signatureAnimationDuration: TimeInterval = 0.30

	@IBOutlet private weak var picturePinStackView: UIStackView!
	@IBOutlet private weak var portraitImageView: ProgressImageView!
	@IBOutlet private weak var portraitEffectView: RoundedVisualEffectView!
	@IBOutlet private weak var ageLabel: UILabel!
	@IBOutlet private weak var genderLabel: UILabel!
	@IBOutlet private weak var pinButton: UIButton!
	@IBOutlet private weak var traitsButton: UIButton!
	@IBOutlet private weak var gradientView: GradientView!
	@IBOutlet private weak var peerIDLabel: UILabel!
	@IBOutlet private weak var bioTextView: UITextView!
	@IBOutlet private weak var bioHeadingLabel: UILabel!
	@IBOutlet private weak var reportButton: UIBarButtonItem!
	@IBOutlet private weak var signatureLabel: UILabel!
	
	@IBOutlet private weak var ageTagView: RoundedRectView!
	@IBOutlet private weak var genderTagView: RoundedRectView!
	@IBOutlet private weak var tagsStackView: UIStackView!
	@IBOutlet private weak var pinAndTagsStackView: UIStackView!

	@IBOutlet private var bioHeightZeroConstraint: NSLayoutConstraint!
	@IBOutlet private weak var signatureToBioConstraint: NSLayoutConstraint!

	@IBOutlet weak var portraitTrailingConstraint: NSLayoutConstraint!
	@IBOutlet weak var portraitLeadingConstraint: NSLayoutConstraint!
	@IBOutlet weak var portraitTopConstraint: NSLayoutConstraint!
	@IBOutlet weak var portraitBottomConstraint: NSLayoutConstraint!


	// properties for the biography animation
	private var bioAnimationTranslationY: CGFloat = 0.0
	private var animationStateWhenBegan = BiographyViewState(wasCompact: false, hideBioContent: false, wasAnimatingGradient: false) // just initialized with something
	private var _bioAnimator: Any!
	@available(iOS 10.0, *)
	private var bioAnimator: UIViewPropertyAnimator? { return _bioAnimator as? UIViewPropertyAnimator }
	private var _signatureAnimator: Any!
	@available(iOS 10.0, *)
	private var signatureAnimator: UIViewPropertyAnimator? { return _signatureAnimator as? UIViewPropertyAnimator }

	static let storyboardID = "PersonDetailViewController"
	static let beaconSegueID = "beaconSegue"

	private var notificationObservers: [NSObjectProtocol] = []
	
	private var pictureProgressManager: ProgressManager?
	private var bioProgressManager: ProgressManager?

	@IBAction func reportPeer(_ sender: Any) {
		let alertController = UIAlertController(title: NSLocalizedString("Report or Unpin", comment: "Title of alert"), message: NSLocalizedString("Mark the content of this user as inappropriate or unpin them to no longer receive messages.", comment: "Message of alert"), preferredStyle: UIAlertController.Style.alert)
		alertController.preferredAction = alertController.addCancelAction()
		let unpinAction = UIAlertAction(title: NSLocalizedString("Unpin", comment: "Alert action button title"), style: .default) { (action) in
			AccountController.use { $0.unpin(id: self.idModel.id) }
		}
		unpinAction.isEnabled = !model.peerID.isLocalPeer && idModel.pinState.isPinned
		alertController.addAction(unpinAction)
		let reportAction = UIAlertAction(title: NSLocalizedString("Report Portrait", comment: "Alert action button title"), style: .destructive) { (action) in
			let mdl = self.model
			AccountController.use { ac in
				ac.report(model: mdl) { (error) in
					InAppNotificationController.display(openapiError: error, localizedTitle: NSLocalizedString("Reporting Portrait Failed", comment: "Title of alert dialog"))
				}
			}
		}
		reportAction.isEnabled = !model.peerID.isLocalPeer && model.info.hasPicture && model.cgPicture != nil && model.pictureClassification == .none
		alertController.addAction(reportAction)
		
		alertController.present()
	}

	@IBAction func tapPicture(_ sender: Any) {
		portraitEffectView.effect = nil
	}

	@IBAction func pinPeer(_ sender: UIButton) {
#if SHOWCASE
		AccountController.NotificationName.pinMatch.post(for: model.peerID)
#else
		let mdl = idModel
		guard !mdl.pinState.isPinned else {
			AccountController.use { $0.updatePinStatus(of: mdl.id, force: true) }
			return
		}

		AppDelegate.requestPin(of: peerID)
		updateState()
#endif
	}

	/// The state of the view when biography animation began.
	private struct BiographyViewState {
		let wasCompact: Bool
		let hideBioContent: Bool
		let wasAnimatingGradient: Bool
	}

	/// Preparse the view for the biography animation.
	private func rampUpBiographyAnimation() -> BiographyViewState {
		let wasCompact = picturePinStackView.axis == .horizontal
		let hideBioContent = hideBioContent(for: wasCompact ? .vertical : .horizontal)
		bioTextView.isHidden = false
		signatureLabel.isHidden = false
		peerIDLabel.isHidden = false
		let wasAnimatingGradient = gradientView.animateGradient
		gradientView.animateGradient = false

		// we have to pause the circle updates during the animation to prevent from ugly glitches
		portraitImageView.pauseUpdates = true

		view.layoutIfNeeded()
		return BiographyViewState(wasCompact: wasCompact, hideBioContent: hideBioContent, wasAnimatingGradient: wasAnimatingGradient)
	}

	private func finalizeBiographyAnimation(from state: BiographyViewState) {
		bioTextView.isHidden = state.hideBioContent
		peerIDLabel.isHidden = state.hideBioContent
		bioTextView.superview?.setNeedsDisplay()
		// reset animation because frame size changed
		gradientView.animateGradient = state.wasAnimatingGradient

		// restart circle updates and update to the latest state
		portraitImageView.pauseUpdates = false
		pictureProgressManager.map { portraitImageView.progressDidUpdate($0.progress) }
	}

	/// set constraints to desired state. Call this in an animation block.
	private func animateBiographyLayout(from state: BiographyViewState) {
		let wasCompact = state.wasCompact

		picturePinStackView.axis = wasCompact ? .vertical : .horizontal
		picturePinStackView.alignment = wasCompact ? .center : .fill
//		pinAndTagsStackView.spacing = wasCompact ? 16.0 : 8.0
		tagsStackView.axis = wasCompact ? .horizontal : .vertical

		portraitTrailingConstraint.constant = wasCompact ? 16.0 : 6.0
		portraitLeadingConstraint.constant = wasCompact ? 16.0 : 6.0
		portraitTopConstraint.constant = wasCompact ? 16.0 : 6.0
		portraitBottomConstraint.constant = wasCompact ? 16.0 : 6.0

		bioHeightZeroConstraint.isActive = wasCompact
		signatureToBioConstraint.constant = wasCompact ? -64.0 : 8.0

		view.setNeedsLayout()
	}

	/// set direct properties to desired state. Call this in an animation block
	private func animateBiographyProperties(from state: BiographyViewState) {
		bioTextView.alpha = state.hideBioContent ? 0.0 : 1.0
		peerIDLabel.alpha = state.hideBioContent ? 0.0 : 1.0
	}

	@available(iOS 10.0, *)
	func panAnimateBio(_ recognizer: UIPanGestureRecognizer) {
		switch recognizer.state {
		case .began:
			animationStateWhenBegan = rampUpBiographyAnimation()
			bioAnimationTranslationY = picturePinStackView.frame.height
			animateBiographyLayout(from: animationStateWhenBegan)
			_bioAnimator = UIViewPropertyAnimator(duration: PersonDetailViewController.bioAnimationDuration, curve: .easeOut) {
				self.view.layoutIfNeeded()
				self.animateBiographyProperties(from: self.animationStateWhenBegan)
				let translation = self.picturePinStackView.frame.height - self.bioAnimationTranslationY
				self.bioAnimationTranslationY = translation == 0.0 ? 100.0 : translation // prevent division by 0
			}
			_signatureAnimator = UIViewPropertyAnimator(duration: PersonDetailViewController.signatureAnimationDuration, curve: .easeOut) {
				self.signatureLabel.alpha = self.animationStateWhenBegan.hideBioContent ? 0.0 : 1.0
			}
			bioAnimator?.pauseAnimation()
			signatureAnimator?.pauseAnimation()
		case .changed:
			let translation = recognizer.translation(in: view)
			bioAnimator?.fractionComplete = translation.y / bioAnimationTranslationY
			let delay = PersonDetailViewController.bioAnimationDuration - PersonDetailViewController.signatureAnimationDuration
			let delayFraction = CGFloat(delay / PersonDetailViewController.bioAnimationDuration)
			if bioAnimationTranslationY < 0.0 { // drag to top: delay animation
				signatureAnimator?.fractionComplete = max(translation.y / bioAnimationTranslationY - delayFraction, 0.0)
			} else { // drag to bottom: finish animation early
				signatureAnimator?.fractionComplete = max(translation.y / bioAnimationTranslationY + delayFraction, 0.0)
			}
		case .ended:
			let translation = recognizer.translation(in: view)
			let mainFractionComplete = translation.y / bioAnimationTranslationY
			let reverse = mainFractionComplete < 0.5
			bioAnimator?.isReversed = reverse
			signatureAnimator?.isReversed = reverse
			let oldState = self.animationStateWhenBegan
			bioAnimator?.addCompletion { _ in
				let reversedState = BiographyViewState(wasCompact: !oldState.wasCompact, hideBioContent: !oldState.hideBioContent, wasAnimatingGradient: oldState.wasAnimatingGradient)
				let completionState = reverse ? reversedState : oldState
				if reverse {
					// we need to set the constraints back
					self.animateBiographyLayout(from: reversedState)
				}
				self.finalizeBiographyAnimation(from: completionState)
				self.signatureLabel.isHidden = completionState.hideBioContent
			}
			bioAnimator?.continueAnimation(withTimingParameters: nil, durationFactor: 0)
			signatureAnimator?.continueAnimation(withTimingParameters: nil, durationFactor: 0)
		default:
			break
		}
	}

	@IBAction func panBiography(_ recognizer: UIPanGestureRecognizer) {
		if #available(iOS 10.0, *) { panAnimateBio(recognizer) }
	}

	@IBAction func tapBiography(_ sender: Any) {
		let state = rampUpBiographyAnimation()

		UIView.animate(withDuration: PersonDetailViewController.signatureAnimationDuration, delay: PersonDetailViewController.bioAnimationDuration - PersonDetailViewController.signatureAnimationDuration, options: [.curveEaseInOut]) { [self] in
			signatureLabel.alpha = state.hideBioContent ? 0.0 : 1.0
		} completion: { [self] (completed) in
			signatureLabel.isHidden = state.hideBioContent
		}

		animateBiographyLayout(from: state)
		UIView.animate(withDuration: PersonDetailViewController.bioAnimationDuration, delay: 0.0, options: [.curveEaseInOut]) { [self] in
			self.view.layoutIfNeeded()
			self.animateBiographyProperties(from: state)
		} completion: { [self] (_) in
			finalizeBiographyAnimation(from: state)
		}
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		(segue.destination as? PeerObserverContainer)?.peerID = peerID
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		pinButton?.setTitle(NSLocalizedString("Pinned", comment: "Button title in 'selected' state"), for: .selected)
		if #available(iOS 14, *) {
			// SF-Symbols work
		} else {
			reportButton.title = NSLocalizedString("Report", comment: "Report Bar Button Title")
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		updateState()
		
		let simpleStateUpdate = { [weak self] (notification: Notification) in
			guard let peerID = notification.userInfo?[PeerID.NotificationInfoKey] as? PeerID,
				  let strongSelf = self, strongSelf.peerID == peerID else { return }

			strongSelf.updateState()
		}
		
		notificationObservers.append(PeeringController.Notifications.peerAppeared.addObserver(usingBlock: simpleStateUpdate))
		notificationObservers.append(PeeringController.Notifications.peerDisappeared.addObserver(usingBlock: simpleStateUpdate))
		notificationObservers.append(PeereeIdentityViewModel.NotificationName.pinStateUpdated.addObserver(usingBlock: simpleStateUpdate))
		notificationObservers.append(AccountController.NotificationName.peerReported.addObserver(usingBlock: simpleStateUpdate))

		notificationObservers.append(AccountController.NotificationName.pinMatch.addObserver(usingBlock: { [weak self] (notification) in
			simpleStateUpdate(notification)
			self?.gradientView?.animateGradient = true
		}))

		notificationObservers.append(AccountController.NotificationName.unpinned.addObserver(usingBlock: { (notification) in
			simpleStateUpdate(notification)
		}))

		notificationObservers.append(AccountController.NotificationName.unmatch.addObserver(usingBlock: { [weak self] (notification) in
			simpleStateUpdate(notification)
			self?.gradientView?.animateGradient = false
		}))

		notificationObservers.append(PeerViewModel.NotificationName.biographyLoaded.addObserver(usingBlock: { (notification) in
			simpleStateUpdate(notification)
		}))
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		let loadPicture = model.cgPicture == nil && model.info.hasPicture
		let loadBio = model.biography == ""

		interactWithPeer { interaction in
			if loadBio {
				interaction.loadBio { bioProgress in
					DispatchQueue.main.async {
						bioProgress.map { self.bioProgressManager = ProgressManager(progress: $0, delegate: self, queue: DispatchQueue.main) }
					}
				}
			}
			if loadPicture {
				interaction.loadPicture { pictureProgress in
					DispatchQueue.main.async {
						self.portraitImageView.loadProgress = pictureProgress
						pictureProgress.map { self.pictureProgressManager = ProgressManager(progress: $0, delegate: self, queue: DispatchQueue.main) }
					}
				}
			}
		}

		gradientView.animateGradient = idModel.pinState == .pinMatch
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
	}

	// MARK: ProgressManagerDelegate

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
			updateState()
		}
	}

	// MARK: Private methods

	private func hideOrShowPinRelatedViews() {
		let hideBioContent = hideBioContent(for: picturePinStackView.axis)
		bioTextView.isHidden = hideBioContent
		peerIDLabel.isHidden = hideBioContent
		signatureLabel.isHidden = hideBioContent
	}

	private func hideBioContent(for axis: NSLayoutConstraint.Axis) -> Bool {
		return !(axis == .horizontal)
	}

	private func updateState() {
		let idState = idModel
		let state = model
		let info = model.info

		let pinActionInProgress = idState.pinState == .pinning || idState.pinState == .unpinning
		if #available(iOS 15.0, *) {
			pinButton.configuration?.showsActivityIndicator = pinActionInProgress
		}

#if SHOWCASE
		pinButton.isEnabled = true
		pinButton.isSelected = true
#else
		pinButton.isEnabled = !state.peerID.isLocalPeer && !pinActionInProgress
		pinButton.isSelected = idState.pinState.isPinned
#endif

		peerIDLabel.text = model.peerID.uuidString
		bioTextView.text = model.biography
		hideOrShowPinRelatedViews()

		title = info.nickname
		navigationItem.title = info.nickname

		signatureLabel.text = info.nickname
		ageLabel.text = info.age.map { (theAge) -> String in "\(theAge)" }
		ageTagView.isHidden = info.age == nil
		genderLabel.text = info.gender.localizedRawValue
		portraitImageView.image = state.portraitOrPlaceholder
		switch state.pictureClassification {
			case .none, .objectionable:
				portraitEffectView.effect = nil
			case .pending:
				portraitEffectView.effect = UIBlurEffect(style: UIBlurEffect.Style.light)
		}
		if #available(iOS 11.0, *) {
			portraitImageView.accessibilityIgnoresInvertColors = state.picture != nil
		}
	}
}
