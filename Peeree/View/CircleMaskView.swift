//
//  CircleMaskView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 01.02.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

class CircleMaskView: UIView {
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

class RoundedImageView: UIImageView {
	override func layoutSubviews() {
		super.layoutSubviews()
		layer.cornerRadius = bounds.width / 2.0
		layer.masksToBounds = true
	}
}

final class ProgressImageView: RoundedImageView, ProgressManagerDelegate {
	private var progressManager: ProgressManager? = nil
	private var circleLayer: CAShapeLayer!
	
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
		
	// MARK: ProgressDelegate
	
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
			} else if let circle = circleLayer {
				circle.strokeEnd = CGFloat(progress.fractionCompleted)
				if #available(iOS 13, *) {
					circle.setNeedsDisplay()
				}
			}
		}
	}
}

final class RoundedVisualEffectView: UIVisualEffectView {
	override func layoutSubviews() {
		super.layoutSubviews()
		layer.cornerRadius = bounds.width / 2.0
		layer.masksToBounds = true
	}
}

class GradientView: UIView {
	open var gradient: CAGradientLayer? { return layer.sublayers?.first as? CAGradientLayer }
	
	@IBInspectable open var startColor: UIColor = UIColor(white: 0.8, alpha: 1.0) {
		didSet { gradient?.colors = [startColor, endColor]; setNeedsDisplay() }
	}
	@IBInspectable open var endColor: UIColor = UIColor(white: 1.0, alpha: 1.0) {
		didSet { gradient?.colors = [startColor, endColor]; setNeedsDisplay() }
	}
	
	open var animateGradient: Bool {
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

//class GradientView: UIView {
//	@IBInspectable open var startColor: UIColor = UIColor(white: 0.8, alpha: 1.0) {
//		didSet { gradient?.colors = [startColor, endColor]; setNeedsDisplay() }
//	}
//	@IBInspectable open var endColor: UIColor = UIColor(white: 1.0, alpha: 1.0) {
//		didSet { gradient?.colors = [startColor, endColor]; setNeedsDisplay() }
//	}
//
//	private var gradient: CAGradientLayer? = nil
//
//	open var animateGradient: Bool {
//		get { gradient != nil }
//		set {
//			guard newValue != animateGradient else { return }
//			guard newValue else {
//				gradient?.removeAllAnimations()
//				gradient?.removeFromSuperlayer()
//				gradient = nil
//				return
//			}
//			let gradient = CAGradientLayer()
//			gradient.frame = bounds
//			gradient.type = CAGradientLayerType.radial
//			gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
//			gradient.endPoint = CGPoint(x: 0.0, y: 1.0)
//
//			gradient.colors = [startColor, endColor]
//			gradient.locations = [NSNumber(floatLiteral: 0.75), NSNumber(floatLiteral: 1.0)]
//
//			if !UIAccessibility.isReduceMotionEnabled {
//				let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
//				opacityAnimation.values = [NSNumber(floatLiteral: 0.5), NSNumber(floatLiteral: 1.0), NSNumber(floatLiteral: 0.5)]
//				opacityAnimation.duration = 3.0
//				opacityAnimation.repeatCount = Float.greatestFiniteMagnitude
//
//				gradient.add(opacityAnimation, forKey: "opacity")
//			}
//
//			//layer.insertSublayer(gradient, at: 0)
//			layer.addSublayer(gradient)
//			self.gradient = gradient
//		}
//	}
//
//	override func layoutSubviews() {
//		super.layoutSubviews()
//		gradient?.frame = bounds
//		gradient?.setNeedsLayout()
//		gradient?.setNeedsDisplay()
//	}
//}
