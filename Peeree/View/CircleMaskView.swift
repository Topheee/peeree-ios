//
//  CircleMaskView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 01.02.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

class ProgressCircleMaskView: CircleMaskView {
    var progress: CGFloat = 0.0
    
    override func drawRect(rect: CGRect) {
        super.drawRect(rect)
        let startAngle = CGFloat(M_PI)
        let endAngle: CGFloat = startAngle+2*CGFloat(M_PI)*(1.0-progress)
        let circle = UIBezierPath(arcCenter: rect.center, radius: rect.width, startAngle: startAngle, endAngle: endAngle, clockwise: true) // TODO localize clockwise
        let context = UIGraphicsGetCurrentContext()
        CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 0.0)
        circle.fill()
    }
}

class CircleMaskView: UIView {
    override func drawRect(rect: CGRect) {
        let circle = UIBezierPath(ovalInRect: rect)
        let context = UIGraphicsGetCurrentContext()
        CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0)
        circle.fill()
    }
    
    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        guard let superBounds = superview?.bounds else { return }
        
        self.bounds = superBounds
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 1.0, alpha: 0.0)
        autoresizingMask = [.FlexibleLeftMargin, .FlexibleRightMargin, .FlexibleTopMargin, .FlexibleBottomMargin]
    }
    
    required init?(coder aDecoder: NSCoder) {
        return nil
    }
}
