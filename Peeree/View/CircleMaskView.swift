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
		//				CGContextSetShadow(context, CGSize(width: 5.0, height: 5.0), 0.7)
		CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0)
		circle.fill()
		//circle.strokeWithBlendMode(.SourceAtop, alpha: 0.5)
	}
	
	init(forView: UIView) {
		super.init(frame: forView.bounds)
		self.backgroundColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
