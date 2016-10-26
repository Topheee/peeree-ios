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
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        let startAngle = CGFloat(M_PI)
        let endAngle: CGFloat = startAngle+2*CGFloat(M_PI)*(1.0-progress)
        let circle = UIBezierPath(arcCenter: rect.center, radius: rect.width, startAngle: startAngle, endAngle: endAngle, clockwise: true) // TODO localize clockwise
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
        circle.fill()
    }
}

class CircleMaskView: UIView {
    
    override func draw(_ rect: CGRect) {
        let circle = UIBezierPath(ovalIn: rect)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        circle.fill()
    }
    
    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        guard let superBounds = superview?.bounds else { return }
        
        self.bounds = superBounds
    }
    
//    override init(frame: CGRect) {
    init(maskedView: UIView) {
        super.init(frame: maskedView.frame)
        backgroundColor = UIColor(white: 1.0, alpha: 0.0)
        autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
//        centerXAnchor.constraint(equalTo: maskedView.centerXAnchor)
//        centerYAnchor.constraint(equalTo: maskedView.centerYAnchor)
//        widthAnchor.constraint(equalTo: maskedView.widthAnchor)
//        heightAnchor.constraint(equalTo: maskedView.heightAnchor)
        maskedView.mask = self
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}
