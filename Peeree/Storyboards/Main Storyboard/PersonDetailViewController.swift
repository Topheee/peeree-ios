//
//  PersonDetailViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class PersonDetailViewController: UIViewController, ProgressDelegate, UITextFieldDelegate {
	@IBOutlet private weak var portraitImageView: UIImageView!
	@IBOutlet private weak var portraitEffectView: UIVisualEffectView!
	@IBOutlet private weak var ageLabel: UILabel!
	@IBOutlet private weak var genderLabel: UILabel!
	@IBOutlet private weak var verificationStatusLabel: UILabel!
	@IBOutlet private weak var verificationImage: UIImageView!
	@IBOutlet private weak var pinButton: UIButton!
    @IBOutlet private weak var traitsButton: UIButton!
    @IBOutlet private weak var gradientView: UIView!
    @IBOutlet private weak var pinIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var findButtonItem: UIBarButtonItem!
	@IBOutlet private weak var peerStackView: UIStackView!
	@IBOutlet private weak var propertyStackView: UIStackView!
	// Text field used for typing text messages to send to peers
	@IBOutlet private weak var messageComposeTextField: UITextField!
	// Button for executing the message send.
	@IBOutlet private weak var sendMessageButton: UIBarButtonItem!
	@IBOutlet private weak var messageTableHeight: NSLayoutConstraint!
//	@IBOutlet private weak var messageTableBottom: NSLayoutConstraint!
	@IBOutlet private weak var chatTableViewContainer: UIView!
	
    private static let unwindSegueID = "unwindToBrowseViewController"
    static let storyboardID = "PersonDetailViewController"
    static let beaconSegueID = "beaconSegue"
	
	private var chatTableView: UITableView? { return chatTableViewContainer.subviews.first as? UITableView }
	
	private var timer: Timer?
    
    private var notificationObservers: [NSObjectProtocol] = []

	private var pinMatchGradientLayer: CAGradientLayer?
    private var circleLayer: CAShapeLayer!
    
    private var pictureProgressManager: ProgressManager?
	
	/// caches
	private var displayedPeerInfo: PeerInfo?
	var peerManager: PeerManager!
	
	@IBAction func reportPeer(_ sender: Any) {
		guard let manager = self.peerManager, let peer = manager.peerInfo else { return }
		let alertController = UIAlertController(title: NSLocalizedString("Report or Unpin", comment: "Title of alert"), message: NSLocalizedString("Mark the content of this user as inappropriate or unpin them to no longer receive messages.", comment: "Message of alert"), preferredStyle: UIAlertController.Style.alert)
		alertController.preferredAction = alertController.addCancelAction()
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Unpin", comment: "Alert action button title"), style: .default) { (action) in
			AccountController.shared.unpin(peer: peer)
        })
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Report Portrait", comment: "Alert action button title"), style: .destructive) { (action) in
			AccountController.shared.report(manager: manager) { (error) in
				AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Reporting Portrait Failed", comment: "Title of alert dialog"))
			}
        })
		
        alertController.present()
	}
	
	// Action method when user presses "send"
	@IBAction func sendMessageTapped(sender: Any) {
		guard let message = messageComposeTextField.text, message != "" else { return }
		
		self.messageComposeTextField.text = ""
		
		self.sendMessageButton.isEnabled = false
		peerManager.send(message: message) { error in
			if let error = error {
				AppDelegate.display(networkError: error, localizedTitle: NSLocalizedString("Sending Message Failed", comment: "Title of alert dialog"))
				self.messageComposeTextField.text = message
				self.messageComposeTextField.resignFirstResponder() // quick fix to toolbar disappearing bug (due to re-layouting when displaying the error)
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
		if messageComposeTextField.isFirstResponder {
			// provide more space for the chat
			messageComposeTextField.resignFirstResponder()
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
    }
    
	override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // make sure that we always have the latest PeerInfo here, because, e.g. when coming back from Find View the portrait may have been loaded meanwhile and as we have value semantics this change is not populated to our displayedPeerInfo variable
        if peerManager != nil {
            displayedPeerInfo = peerManager.peerInfo ?? displayedPeerInfo
        }
        
        updateState()
        
        let simpleStateUpdate = { (notification: Notification) in
            guard let peerID = notification.userInfo?[PeeringController.NotificationInfoKey.peerID.rawValue] as? PeerID else { return }
            guard self.displayedPeerInfo?.peerID == peerID else { return }
            // as we have value semantics, our cached peer info does not change, so we have to get the updated one
            self.displayedPeerInfo = self.peerManager.peerInfo ?? self.displayedPeerInfo
            self.updateState()
        }
        
		notificationObservers.append(PeeringController.Notifications.peerAppeared.addObserver(usingBlock: simpleStateUpdate))
		notificationObservers.append(PeeringController.Notifications.peerDisappeared.addObserver(usingBlock: simpleStateUpdate))
		notificationObservers.append(PeerManager.Notifications.verified.addObserver(usingBlock: simpleStateUpdate))
		
		let simpleHandledNotifications2: [AccountController.Notifications] = [.pinned, .pinningStarted, .pinFailed, .unpinned, .unpinFailed, .pinStateUpdated, .peerReported]
        for networkNotification in simpleHandledNotifications2 {
            notificationObservers.append(networkNotification.addObserver(usingBlock: simpleStateUpdate))
        }
        
        notificationObservers.append(AccountController.Notifications.pinMatch.addObserver(usingBlock: { (notification) in
            simpleStateUpdate(notification)
            self.animateGradient()
        }))
		
		notificationObservers.append(UIApplication.willResignActiveNotification.addObserver { (notification) in
			if self.messageComposeTextField.isFirstResponder {
				self.shiftedToolbarFrame = self.navigationController?.toolbar?.frame
			}
		})
		notificationObservers.append(UIApplication.didBecomeActiveNotification.addObserver { (notification) in
			if let frame = self.shiftedToolbarFrame {
				self.navigationController?.toolbar?.frame = frame
			}
			self.shiftedToolbarFrame = nil
		})
		
		registerForKeyboardNotifications()
		
		// TODO test whether we really still need this, because probably not because of new stack view
//		if #available(iOS 11, *) {
//			// reset it's frame on iOS 11 as the view is not layed out there every time it gets active again
//			pinButton.superview!.setNeedsLayout()
//		}
		
		// somehow sometimes it is still hidden from BrowseViewController
		navigationController?.setNavigationBarHidden(false, animated: false)
    }
	
	private var shiftedToolbarFrame: CGRect? = nil
	private var originalToolbarFrame = CGRect.zero
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let peer = displayedPeerInfo else { return }
		
		originalToolbarFrame = navigationController?.toolbar.frame ?? originalToolbarFrame
		animatePictureLoadLayer()
		animateGradient()
		
		if peerManager.transcripts.count > 0 {
			layoutMetadata(isHorizontal: true)
			chatTableView?.scrollToBottom(animated: true)
		}
		
		// somehow the animation does not work directly when viewDidAppear is called for the first time, probably because AppDelegate instantiates it via code
		guard !UIAccessibility.isReduceMotionEnabled && peer.pinned else { return }
		timer = Timer.scheduledTimer(timeInterval: peer.pinned ? 0.5 : 5.0, target: self, selector: #selector(animatePinButton(timer:)), userInfo: nil, repeats: false)
    }

	private func resizePortraitViews() {
		portraitEffectView.layer.cornerRadius = portraitEffectView.frame.width / 2
		portraitEffectView.layer.masksToBounds = true
		portraitImageView.layer.cornerRadius = portraitImageView.frame.width / 2
		portraitImageView.layer.masksToBounds = true
		resizeCircleLayer()
		resizeGradientLayer()
	}
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizePortraitViews()
		
        updateState()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
		NotificationCenter.default.removeObserver(self)
        for observer in notificationObservers { NotificationCenter.`default`.removeObserver(observer) }
        notificationObservers.removeAll()
		navigationController?.setToolbarHidden(true, animated: true)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pictureProgressManager = nil
		removeGradient()
        removePictureLoadLayer()
        portraitImageView.image = nil
		
		// reset position from animation, if the user slides back in
		timer?.invalidate()
		timer = nil
		pinButton.layer.removeAllAnimations()
		
		// reverse toolbar modifications, otherwise the toolbar disappears when going into Radar view and back
		messageComposeTextField.resignFirstResponder()
		messageTableHeight.isActive = false
//		messageTableBottom.constant = 0.0
    }
	
	// MARK: UITextFieldDelegate methods
	
	// Override to dynamically enable/disable the send button based on user typing
	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		let length = (textField.text?.count ?? 0) - range.length + string.count;
		self.sendMessageButton.isEnabled = length > 0
		return true
	}
	
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		sendMessageTapped(sender: textField)
		return true
	}
	
    // MARK: ProgressDelegate
    
	func progressDidPause(_ progress: Progress) {
        // ignored
    }
    
    func progressDidCancel(_ progress: Progress) {
        if progress === pictureProgressManager?.progress {
            pictureProgressManager = nil
            removePictureLoadLayer()
//            UIView.animate(withDuration: 1.0, delay: 0.0, options: [.autoreverse], animations: {
//                self.portraitImageView.backgroundColor = UIColor.red
//            })
            // as above is not working...
            UIView.animate(withDuration: 1.0, delay: 0.0, options: [], animations: {
                self.portraitImageView.backgroundColor = UIColor.red
            }) { (completed) in
                UIView.animate(withDuration: 1.0, delay: 0.0, options: [], animations: {
                    self.portraitImageView.backgroundColor = nil
                }, completion: nil)
            }
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
                removePictureLoadLayer()
                updateState()
            } else if let circle = circleLayer {
                circle.strokeEnd = CGFloat(progress.fractionCompleted)
				if #available(iOS 13, *) {
					circle.setNeedsDisplay()
				}
            }
        }
    }

    // MARK: Private methods
	
    private func updateState() {
        guard let peer = displayedPeerInfo, let state = peerManager else { return }
		
		navigationController?.isToolbarHidden = !peer.pinMatched || state.isLocalPeer
        pinButton.isHidden = state.pinState == .pinning || peerStackView.axis == .horizontal
        pinButton.isEnabled = state.isAvailable && !state.isLocalPeer
        pinButton.isSelected = state.pinState == .pinned
//        traitsButton.isHidden = state.peerInfoDownloadState != .downloaded
        pinIndicator.isHidden = state.pinState != .pinning || peerStackView.axis == .horizontal
//        findButtonItem.isEnabled = peer.pinMatched
		sendMessageButton.isEnabled = state.isAvailable && messageComposeTextField.text?.count ?? 0 > 0
        
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
    
    private func removePictureLoadLayer() {
        circleLayer?.removeFromSuperlayer()
        circleLayer = nil
    }
	
	private func animatePictureLoadLayer() {
		guard let peer = displayedPeerInfo, let progress = PeeringController.shared.manager(for: peer.peerID).loadPicture() else { return }
		
		pictureProgressManager = ProgressManager(progress: progress, delegate: self, queue: DispatchQueue.main)
		
		// Setup the CAShapeLayer with the path, colors, and line width
		circleLayer = CAShapeLayer()
		resizeCircleLayer()
		
		circleLayer.fillColor = UIColor.clear.cgColor
		circleLayer.strokeColor = AppTheme.tintColor.cgColor
		circleLayer.lineWidth = 5.0
		circleLayer.lineCap = CAShapeLayerLineCap.round
		circleLayer.strokeEnd = CGFloat(progress.fractionCompleted)
		
		// Add the circleLayer to the view's layer's sublayers
		portraitImageView.layer.addSublayer(circleLayer)
	}
	
	private func resizeCircleLayer() {
		guard let circleLayer = circleLayer else { return }
		
		// localize clockwise progress drawing
		let clockwiseProgress: Bool
		if let langCode = Locale.current.languageCode {
			let direction = Locale.characterDirection(forLanguage: langCode)
			clockwiseProgress = direction == .leftToRight || direction == .topToBottom
		} else {
			clockwiseProgress = true
		}
		let size = portraitImageView.bounds.size
		let circlePath = UIBezierPath(arcCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0 - size.height * 0.075),
									  radius: size.width * 0.12, startAngle: clockwiseProgress ? .pi * CGFloat(0.5) : .pi * CGFloat(2.5),
									  endAngle: clockwiseProgress ? .pi * CGFloat(2.5) : .pi * CGFloat(0.5), clockwise: clockwiseProgress)
		circleLayer.frame = portraitImageView.bounds
		circleLayer.path = circlePath.cgPath
		circleLayer.setNeedsLayout()
		circleLayer.setNeedsDisplay()
	}
	
	private func animateGradient() {
		guard displayedPeerInfo?.pinMatched ?? false else { return }
		
		let waveColor = AppTheme.backgroundColor.cgColor
		let valleyColor = AppTheme.tintColor.cgColor
		let view = gradientView!
		let gradient = CAGradientLayer()
		pinMatchGradientLayer = gradient
		gradient.frame = view.bounds
		gradient.type = CAGradientLayerType.radial
		gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
		gradient.endPoint = CGPoint(x: 0.0, y: 1.0)
		
		gradient.colors = [valleyColor, waveColor]
		gradient.locations = [NSNumber(floatLiteral: 0.75), NSNumber(floatLiteral: 1.0)]
		
		if !UIAccessibility.isReduceMotionEnabled {
			let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
			opacityAnimation.values = [NSNumber(floatLiteral: 0.5), NSNumber(floatLiteral: 1.0), NSNumber(floatLiteral: 0.5)]
			opacityAnimation.duration = 3.0
			opacityAnimation.repeatCount = Float.greatestFiniteMagnitude
			
			gradient.add(opacityAnimation, forKey: "opacity")
		}
		
		view.layer.insertSublayer(gradient, at: 0)
	}
	
	private func resizeGradientLayer() {
		pinMatchGradientLayer?.frame = gradientView.bounds
		pinMatchGradientLayer?.setNeedsLayout()
		pinMatchGradientLayer?.setNeedsDisplay()
	}
	
	private func removeGradient() {
		pinMatchGradientLayer?.removeAllAnimations()
		pinMatchGradientLayer?.removeFromSuperlayer()
		pinMatchGradientLayer = nil
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
		self.layoutMetadata(isHorizontal: true)
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
		guard let userInfo = keyboardNotification.userInfo, let toolbar = self.navigationController?.toolbar else { return }
		
		let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! CGRect
		let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as! NSNumber
		let animationCurveNumber = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as! NSNumber
		let animationCurve = UIView.AnimationCurve(rawValue: animationCurveNumber.intValue) ?? UIView.AnimationCurve.easeOut
		
		// Animate up or down
		UIView.beginAnimations(nil, context: nil)
		UIView.setAnimationDuration(animationDuration.doubleValue)
		UIView.setAnimationCurve(animationCurve)
		UIView.setAnimationDelegate(self)
		UIView.setAnimationDidStop(#selector(toolbarAnimationCompletion))
		
		// since the notification is triggered a second time when the user switches to emojis, we cannot simply use `toolbar.frame`:
		let toolbarFrame = originalToolbarFrame
		toolbar.frame = CGRect(x: toolbarFrame.origin.x, y: toolbarFrame.origin.y + (keyboardFrame.size.height * (up ? -1 : 1)), width: toolbarFrame.size.width, height: toolbarFrame.size.height)
		messageTableHeight.isActive = up
//		messageTableBottom.constant = up ? keyboardFrame.size.height : 0.0
		UIView.commitAnimations()
		if up {
			chatTableView?.scrollToBottom(animated: true)
		}
	}
	
	@objc func toolbarAnimationCompletion(animationID: String, finished: NSNumber, context: UnsafeRawPointer) {
		resizePortraitViews()
	}
	
	private func layoutMetadata(isHorizontal: Bool) {
		guard self.peerStackView.axis == (isHorizontal ? .vertical : .horizontal) else { return /* nothing changed */ }
		
		removeGradient()
		removePictureLoadLayer()
		
		UIView.animate(withDuration: 0.25, animations: { () -> Void in
			self.pinButton.isHidden = true
			self.pinIndicator.isHidden = true
			self.peerStackView.axis = isHorizontal ? .horizontal : .vertical
			self.propertyStackView.axis = isHorizontal ? .vertical : .horizontal
			self.propertyStackView.alignment = isHorizontal ? .leading : .center
			self.chatTableViewContainer.isHidden = !isHorizontal
			self.resizePortraitViews()
		}, completion: { _ in
			self.animatePictureLoadLayer()
			self.animateGradient()
			self.updateState()
			self.resizePortraitViews()
		})
	}
}
