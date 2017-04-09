//
//  CircleMaskView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 01.02.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

/// This class is currently UNUSED
class ProgressCircleMaskView: CircleMaskView {
    var progress: CGFloat = 0.0
    let clockwiseProgress: Bool
    
    override init(maskedView: UIView) {
        if let langCode = Locale.current.languageCode {
            let direction = Locale.characterDirection(forLanguage: langCode)
            clockwiseProgress = direction == .leftToRight || direction == .topToBottom
        } else {
            clockwiseProgress = true
        }
        
        super.init(maskedView: maskedView)
    }
    
    required init?(coder aDecoder: NSCoder) {
        if let langCode = Locale.current.languageCode {
            let direction = Locale.characterDirection(forLanguage: langCode)
            clockwiseProgress = direction == .leftToRight || direction == .topToBottom
        } else {
            clockwiseProgress = false
        }
        
        super.init(coder: aDecoder)
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        let startAngle = CGFloat.pi
        let endAngle: CGFloat = startAngle + 2 * CGFloat.pi * (1.0 - progress)
        let circle = UIBezierPath(arcCenter: rect.center, radius: rect.width, startAngle: startAngle, endAngle: endAngle, clockwise: clockwiseProgress)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(AppDelegate.shared.theme.globalTintColor.cgColor)
        circle.fill()
//        context?.setFillColor(UIColor.clear.cgColor)
//        context?.setStrokeColor(AppDelegate.shared.theme.globalTintColor.cgColor)
//        circle.stroke()
    }
}

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
