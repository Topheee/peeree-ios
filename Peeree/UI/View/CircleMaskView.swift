//
//  CircleMaskView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 01.02.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

/// A view containing a filled circle, which applies itself to another view.
final class CircleMaskView: UIView {
	override func draw(_ rect: CGRect) {
		let circle = UIBezierPath(ovalIn: rect)
		let context = UIGraphicsGetCurrentContext()
		context?.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
		circle.fill()
	}
	
	init(maskedView: UIView) {
		super.init(frame: maskedView.bounds)
		maskedView.mask = self
		backgroundColor = UIColor(white: 1.0, alpha: 0.0)
		autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
	}
	
	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
}

/// A view containing a filled circle.
@IBDesignable @objc
final class CircleView: UIView {
	override func draw(_ rect: CGRect) {
		let circle = UIBezierPath(ovalIn: rect.inset(by: circleInsets))
		guard let context = UIGraphicsGetCurrentContext() else { return }
		if #available(iOS 13.0, *) {
			context.setFillColor(fillColor?.cgColor ?? UIColor.systemBackground.cgColor)
		} else {
			context.setFillColor(fillColor?.cgColor ?? UIColor.white.cgColor)
		}
		circle.fill()
		if let color = strokeColor {
			circle.lineWidth = strokeWidth
			context.setStrokeColor(color.cgColor)
			circle.stroke()
		}
	}
	
	@IBInspectable var fillColor: UIColor? {
		didSet { setNeedsDisplay() }
	}
	@IBInspectable var strokeColor: UIColor? {
		didSet { setNeedsDisplay() }
	}
	
	@IBInspectable var circleRadius: CGFloat = 24.0 {
		didSet { setNeedsDisplay() }
	}

	@IBInspectable var strokeWidth: CGFloat = 1.0 {
		didSet { setNeedsDisplay() }
	}

	@IBInspectable var topEdgeInset: CGFloat {
		get { return circleInsets.top }
		set { circleInsets.top = newValue
		}
	}
	@IBInspectable var leftEdgeInset: CGFloat {
		get { return circleInsets.left }
		set { circleInsets.left = newValue
		}
	}
	@IBInspectable var bottomEdgeInset: CGFloat {
		get { return circleInsets.bottom }
		set { circleInsets.bottom = newValue
		}
	}
	@IBInspectable var rightEdgeInset: CGFloat {
		get { return circleInsets.right }
		set { circleInsets.right = newValue
		}
	}

	var circleInsets: UIEdgeInsets = .zero {
		didSet { setNeedsDisplay() }
	}

	override var intrinsicContentSize: CGSize {
		return CGSize(width: circleRadius, height: circleRadius)
	}
}

/// A view containing a filled circle.
@IBDesignable @objc
final class RoundedRectView: UIView {
	override func draw(_ rect: CGRect) {
		let roundedRect = rect.inset(by: circleInsets)
		let circle = UIBezierPath(roundedRect: roundedRect, cornerRadius: cornerRadius < 0.0 ? roundedRect.height / 2.0 : cornerRadius)
		let context = UIGraphicsGetCurrentContext()
		if #available(iOS 13.0, *) {
			context?.setFillColor(fillColor?.cgColor ?? UIColor.systemBackground.cgColor)
		} else {
			context?.setFillColor(fillColor?.cgColor ?? UIColor.white.cgColor)
		}
		circle.fill()
	}
	
	@IBInspectable var fillColor: UIColor? {
		didSet { setNeedsDisplay() }
	}

	@IBInspectable var cornerRadius: CGFloat = 0.0 {
		didSet { setNeedsDisplay() }
	}

	@IBInspectable var topEdgeInset: CGFloat {
		get { return circleInsets.top }
		set { circleInsets.top = newValue
		}
	}
	@IBInspectable var leftEdgeInset: CGFloat {
		get { return circleInsets.left }
		set { circleInsets.left = newValue
		}
	}
	@IBInspectable var bottomEdgeInset: CGFloat {
		get { return circleInsets.bottom }
		set { circleInsets.bottom = newValue
		}
	}
	@IBInspectable var rightEdgeInset: CGFloat {
		get { return circleInsets.right }
		set { circleInsets.right = newValue
		}
	}

	var circleInsets: UIEdgeInsets = .zero {
		didSet { setNeedsDisplay() }
	}

	override var intrinsicContentSize: CGSize {
		return CGSize(width: 28.0, height: 28.0)
	}
}

class RoundedImageView: UIImageView {
	override func layoutSubviews() {
		super.layoutSubviews()
		layer.cornerRadius = bounds.width / 2.0
		layer.masksToBounds = true
	}
}

final class RoundedVisualEffectView: UIVisualEffectView {
	override func layoutSubviews() {
		super.layoutSubviews()
		layer.cornerRadius = bounds.width / 2.0
		layer.masksToBounds = true
	}
}

/// An image view drawing a placeholder and progress until the actual image is being loaded.
final class ProgressImageView: RoundedImageView, ProgressManagerDelegate {
	private var progressManager: ProgressManager? = nil
	private var circleLayer: CAShapeLayer!

	/// Set to `true` to temporarly disable update the `strokeEnd` when the progress updates.
	public var pauseUpdates = false

	public var loadProgress: Progress? {
		get {
			progressManager?.progress
		}
		set {
			if let progress = newValue {
				progressManager = ProgressManager(progress: progress, delegate: self, queue: DispatchQueue.main)
				animatePictureLoadLayer()
			} else {
				progressManager = nil
				removePictureLoadLayer()
			}
		}
	}

	private func removePictureLoadLayer() {
		circleLayer?.removeFromSuperlayer()
		circleLayer = nil
	}
	
	private func animatePictureLoadLayer() {
		removePictureLoadLayer()
		// Setup the CAShapeLayer with the path, colors, and line width
		circleLayer = CAShapeLayer()
		resizeCircleLayer()
		
		circleLayer.fillColor = UIColor.clear.cgColor
		circleLayer.strokeColor = AppTheme.tintColor.cgColor
		circleLayer.lineWidth = 5.0
		circleLayer.lineCap = CAShapeLayerLineCap.round
		circleLayer.strokeEnd = CGFloat(loadProgress?.fractionCompleted ?? 0.0)
		
		// Add the circleLayer to the view's layer's sublayers
		layer.addSublayer(circleLayer)
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
		let size = bounds.size
		let circlePath = UIBezierPath(arcCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0 - size.height * 0.075),
									  radius: size.width * 0.12, startAngle: clockwiseProgress ? .pi * CGFloat(0.5) : .pi * CGFloat(2.5),
									  endAngle: clockwiseProgress ? .pi * CGFloat(2.5) : .pi * CGFloat(0.5), clockwise: clockwiseProgress)
		circleLayer.frame = bounds
		circleLayer.path = circlePath.cgPath
		circleLayer.setNeedsLayout()
		circleLayer.setNeedsDisplay()
	}
	
	override func layoutSubviews() {
		super.layoutSubviews()
		resizeCircleLayer()
	}

	// MARK: ProgressManagerDelegate

	func progressDidPause(_ progress: Progress) { /* ignored */ }
	func progressDidResume(_ progress: Progress) { /* ignored */ }
	
	func progressDidCancel(_ progress: Progress) {
		if progress === loadProgress {
			progressManager = nil
			removePictureLoadLayer()
//			UIView.animate(withDuration: 1.0, delay: 0.0, options: [.autoreverse], animations: {
//				self.portraitImageView.backgroundColor = UIColor.red
//			})
			// as above is not working...
			UIView.animate(withDuration: 1.0, delay: 0.0, options: [], animations: {
				self.backgroundColor = UIColor.red
			}) { (completed) in
				UIView.animate(withDuration: 1.0, delay: 0.0, options: [], animations: {
					self.backgroundColor = nil
				}, completion: nil)
			}
		}
	}
	
	func progressDidUpdate(_ progress: Progress) {
		if progress === loadProgress {
			if progress.completedUnitCount == progress.totalUnitCount {
				progressManager = nil
				removePictureLoadLayer()
			} else if let circle = circleLayer, !pauseUpdates {
				circle.strokeEnd = CGFloat(progress.fractionCompleted)
				if #available(iOS 13, *) {
					circle.setNeedsDisplay()
				}
			}
		}
	}
}

/// Custom view displaying a pulsing two-color radial gradient.
final class GradientView: UIView {
	public var gradient: CAGradientLayer? { return layer.sublayers?.first as? CAGradientLayer }
	
	@IBInspectable public var startColor: UIColor = UIColor(white: 0.8, alpha: 1.0) {
		didSet { gradient?.colors = [startColor, endColor]; setNeedsDisplay() }
	}
	@IBInspectable public var endColor: UIColor = UIColor(white: 1.0, alpha: 1.0) {
		didSet { gradient?.colors = [startColor, endColor]; setNeedsDisplay() }
	}
	
	/// Displays and animates or removes the gradient from the view.
	public var animateGradient: Bool {
		get { gradient != nil }
		set {
			guard newValue != animateGradient else { return }
			guard newValue else {
				gradient?.removeAllAnimations()
				gradient?.removeFromSuperlayer()
				return
			}

			let gradient = CAGradientLayer()
			gradient.frame = bounds
			gradient.type = CAGradientLayerType.radial
			gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
			gradient.endPoint = CGPoint(x: 1.0, y: 1.0)

			gradient.colors = [startColor.cgColor, endColor.cgColor]
			gradient.locations = [NSNumber(floatLiteral: 0.75), NSNumber(floatLiteral: 1.0)]
			gradient.backgroundColor = UIColor.yellow.cgColor

			if !UIAccessibility.isReduceMotionEnabled {
				let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
				opacityAnimation.values = [NSNumber(floatLiteral: 0.5), NSNumber(floatLiteral: 1.0), NSNumber(floatLiteral: 0.5)]
				opacityAnimation.duration = 3.0
				opacityAnimation.repeatCount = Float.greatestFiniteMagnitude

				gradient.add(opacityAnimation, forKey: "opacity")
			}
			layer.insertSublayer(gradient, at: 0)
		}
	}
	
	override func layoutSubviews() {
		super.layoutSubviews()
		gradient?.frame = bounds
	}
}

class ResizingTextView: UITextView {
	override var intrinsicContentSize: CGSize { return contentSize }
}
