//
//  PeereeExtensions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 05.08.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

extension UIAlertController {
    /// This is the preferred method to display an UIAlertController since it sets the tint color of the global theme. 
    func present(_ completion: (() -> Void)?) {
        presentInFrontMostViewController(true, completion: completion)
        self.view.tintColor = theme.globalTintColor
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
        
        UIView.animate(withDuration: duration, delay: delay, usingSpringWithDamping: damping, initialSpringVelocity: velocity, options: UIViewAnimationOptions(rawValue: 0), animations: { () -> Void in
            for (index, view) in views.enumerated() {
                view.frame = positions[index]
                view.alpha = 1.0
            }
        }, completion: nil)
    }
}
