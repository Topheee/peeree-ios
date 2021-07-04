//
//  GenericFunctions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import UIKit

// MARK: - Functions

// MARK: - Extensions

extension UIView {
	var marginFrame: CGRect {
		let margins = self.layoutMargins
		var ret = self.frame
		ret.origin.x += margins.left
		ret.origin.y += margins.top
		ret.size.height -= margins.top + margins.bottom
		ret.size.width -= margins.left + margins.right
		return ret
	}
}

extension UIImage {
	func cropped(to cropRect: CGRect) -> UIImage? {
		let scaledCropRect = CGRect(x: cropRect.origin.x * scale, y: cropRect.origin.y * scale, width: cropRect.size.width * scale, height: cropRect.size.height * scale)
		
		guard let imageRef = self.cgImage?.cropping(to: scaledCropRect) else { return nil }
		return UIImage(cgImage: imageRef, scale: scale, orientation: imageOrientation)
	}

	func roundedCropped(cropRect: CGRect, backgroundColor: UIColor?) -> UIImage? {
		let minImageEdgeLength = min(size.height, size.width)
		guard let croppedImage = cropped(to: CGRect(x: (size.width - minImageEdgeLength) / 2, y: (size.height - minImageEdgeLength) / 2, width: minImageEdgeLength, height: minImageEdgeLength)) else { return nil }
		UIGraphicsBeginImageContextWithOptions(CGSize(squareEdgeLength: cropRect.height), backgroundColor != nil, UIScreen.main.scale)
		croppedImage.draw(in: cropRect)
		let path = UIBezierPath(rect: cropRect)
		// we need to inset the cropRect by 1 such that we avoid an ugly border
		path.append(UIBezierPath(ovalIn: cropRect.inset(by: UIEdgeInsets(top: 1.0, left: 1.0, bottom: 1.0, right: 1.0))))
		path.usesEvenOddFillRule = true
		if let fillColor = backgroundColor {
			fillColor.setFill()
			path.fill()
		}
		let image = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()
		return image
	}
}

extension UIViewController {
	func presentInFrontMostViewController(_ animated: Bool, completion: (() -> Void)?) {
		guard let rootVC = UIApplication.shared.windows.first?.rootViewController else { return }

		var vc = rootVC
		while let presentedVC = vc.presentedViewController {
			vc = presentedVC
		}
		DispatchQueue.main.async {
			vc.present(self, animated: animated, completion: completion)
		}
	}
}

extension UIAlertController {
	/// This is the preferred method to display an UIAlertController since it sets the tint color of the global theme.
	func present(_ completion: (() -> Void)? = nil) {
		presentInFrontMostViewController(true, completion: completion)
		self.view.tintColor = AppTheme.tintColor
	}
}

extension UIView {
	/***
	Animates <code>animations</code> with the same parameters as the keyboard (provided by <code>notification</code>.
	@param notification	A notification object from one the <code>UIResponder.keyboard…Notification</code> notifications.
	*/
	static func animateAlongKeyboard(notification: Notification, animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
		guard let userInfo = notification.userInfo else { return }
		
		let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as! NSNumber
		let animationCurveNumber = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as! NSNumber
		let animationCurve = UIView.AnimationCurve(rawValue: animationCurveNumber.intValue) ?? UIView.AnimationCurve.easeOut
		
		let animationCurveOptions = UIView.AnimationOptions(curve: animationCurve)
		
		UIView.animate(withDuration: animationDuration.doubleValue, delay: 0.0, options: animationCurveOptions, animations: animations, completion: completion)
	}
	
	/**
	 *	Animates views like they are flown in from the bottom of the screen.
	 *	@param views	the views to animate
	 */
	func flyInSubviews(_ views: [UIView], duration: TimeInterval, delay: TimeInterval, damping: CGFloat, velocity: CGFloat) {
		var positions = [CGRect]()
		for value in views {
			positions.append(value.frame)
			value.frame.origin.y = self.frame.height
			value.alpha = 0.0
		}
		
		UIView.animate(withDuration: duration, delay: delay, usingSpringWithDamping: damping, initialSpringVelocity: velocity, options: UIView.AnimationOptions(rawValue: 0), animations: { () -> Void in
			for (index, view) in views.enumerated() {
				view.frame = positions[index]
				view.alpha = 1.0
			}
		}, completion: nil)
	}
}

extension UIView.AnimationOptions {
	init(curve: UIView.AnimationCurve) {
		switch curve {
		case .easeIn:
			self = UIView.AnimationOptions.curveEaseIn
		case .easeOut:
			self = .curveEaseOut
		case .easeInOut:
			self = .curveEaseInOut
		case .linear:
			self = .curveLinear
		default:
			self = []
		}
	}
}


extension UITextField {
	/// cap number of characters to <code>maxUtf8Length</code>. Use in <code>func textField(_: UITextField, shouldChangeCharactersIn: NSRange, replacementString: String) -> Bool</code>
	func allowChangeCharacters(in range: NSRange, replacementString string: String, maxUtf8Length: Int) -> Bool {
		let oldLength = self.text?.utf8.count ?? 0
		if (range.length + range.location > oldLength) {
			return false
		}
		return oldLength + string.utf8.count - range.length <= maxUtf8Length
	}
}

extension UITableView {
	func scrollToBottom(animated: Bool) {
		var numberOfRows = 0
		let nSections = self.numberOfSections
		for section in 0..<nSections {
			numberOfRows = numberOfRows + self.numberOfRows(inSection: section)
		}
		if (numberOfRows > 0) {
			self.scrollToRow(at: IndexPath(row:(numberOfRows - 1), section: nSections-1), at: .bottom, animated: animated)
		}
	}
}

extension UIAlertController {
	func addCancelAction(handler: ((UIAlertAction) -> Void)? = nil) -> UIAlertAction {
		let action = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: handler)
		self.addAction(action)
		return action
	}
}
