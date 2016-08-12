//
//  CircleMaskView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 01.02.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

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
    
    init(forView: UIView) {
        super.init(frame: forView.bounds)
        self.backgroundColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    }
    
    required init?(coder aDecoder: NSCoder) {
        return nil
    }
}

//class CircleMaskView: UIView {
//    let maskedView: UIView
//    
//    override func drawRect(rect: CGRect) {
//        let circle = UIBezierPath(ovalInRect: rect)
//        let context = UIGraphicsGetCurrentContext()
//        CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0)
//        circle.fill()
//    }
//    
//    override func layoutIfNeeded() {
//        super.layoutIfNeeded()
//        
//    }
//    
//    init(forView: UIView) {
//        maskedView = forView
//        super.init(frame: forView.bounds)
//        self.backgroundColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
//    }
//    
//    required init?(coder aDecoder: NSCoder) {
//        return nil
//    }
//}
