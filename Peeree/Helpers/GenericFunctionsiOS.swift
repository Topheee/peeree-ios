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
}

extension UIViewController {
    func presentInFrontMostViewController(_ animated: Bool, completion: (() -> Void)?) {
        guard let rootVC = UIApplication.shared.keyWindow?.rootViewController else { return }
        
        var vc = rootVC
        while vc.presentedViewController != nil {
            vc = vc.presentedViewController!
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
        self.view.tintColor = AppDelegate.shared.theme.globalTintColor
    }
}

extension UIView {
    /**
     *	Animates views like they are flown in from the bottom of the screen.
     *	@param views    the views to animate
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
