//
//  SetupIdentityViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import UIKit

final class SetupIdentityViewController: UIViewController {
	@IBOutlet private weak var launchAppButton: UIButton!
	@IBOutlet private weak var termsSwitch: UISwitch!
	@IBOutlet private weak var termsLinkButton: UIButton!

	@IBAction func viewTerms(_ sender: UIButton) {
		AppDelegate.viewTerms(in: self)
	}

	@IBAction func updateLaunchButton(_ sender: Any) {
		launchAppButton.layer.removeAllAnimations()
		launchAppButton.transform = CGAffineTransform.identity
		launchAppButton.isEnabled = termsSwitch.isOn

		guard termsSwitch.isOn && !UIAccessibility.isReduceMotionEnabled else { return }

		UIView.animate(withDuration: 0.67, delay: 1.2, usingSpringWithDamping: 1.0, initialSpringVelocity: 2.7, options: [.repeat, .autoreverse, .allowUserInteraction], animations: { () -> Void in
			self.launchAppButton.transform = self.launchAppButton.transform.scaledBy(x: 0.96, y: 0.96)
		}, completion: nil)
	}

	@IBAction func finishIntroduction(_ sender: AnyObject) {
		guard termsSwitch.isOn else { return }

		AppDelegate.createIdentity(displayError: false)

		dismiss(animated: true, completion: nil)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		launchAppButton.isEnabled = termsSwitch.isOn

		let termsAgreement = NSLocalizedString("I agree to the ", comment: "Link button text in onboarding")
		let terms = NSLocalizedString("Terms of Use", comment: "Colored link name in button text in onboarding")

		let linkText: NSMutableAttributedString
		if #available(iOS 13, *) {
			linkText = NSMutableAttributedString(string: termsAgreement, attributes: [NSAttributedString.Key.foregroundColor : UIColor.label])
		} else {
			linkText = NSMutableAttributedString(string: termsAgreement, attributes: [NSAttributedString.Key.foregroundColor : UIColor.darkText])
		}
		linkText.append(NSAttributedString(string: terms, attributes: [NSAttributedString.Key.foregroundColor : AppTheme.tintColor]))

		termsLinkButton.setAttributedTitle(linkText, for: .normal)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		guard let vc = segue.destination as? OnboardingDescriptionViewController else { return }

		vc.infoType = .data
	}
}
