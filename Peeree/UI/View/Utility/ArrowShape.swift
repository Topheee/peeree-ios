//
//  ArrowShape.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

// https://stackoverflow.com/questions/75504732/is-there-a-way-to-create-a-curved-arrow-that-connects-two-views-in-swiftui

struct ArrowShape: Shape {
	let from: CGPoint
	let to: CGPoint
	var control: CGPoint

	func path(in rect: CGRect) -> Path {
		var path = Path()
		path.move(to: from)
		path.addQuadCurve(to: to, control: control)

		let angle = atan2(to.y - control.y, to.x - control.x)
		let arrowLength: CGFloat = 15
		let arrowPoint1 = CGPoint(x: to.x - arrowLength * cos(angle - .pi / 6), y: to.y - arrowLength * sin(angle - .pi / 6))
		let arrowPoint2 = CGPoint(x: to.x - arrowLength * cos(angle + .pi / 6), y: to.y - arrowLength * sin(angle + .pi / 6))

		path.move(to: to)
		path.addLine(to: arrowPoint1)
		path.move(to: to)
		path.addLine(to: arrowPoint2)

		return path
	}
}


#Preview {
	let position1: CGPoint = CGPoint(x: 150, y: 150)
	let position2: CGPoint = CGPoint(x: 250, y: 50)

	return ArrowShape(from: CGPoint(x: position1.x - 30 , y: position1.y),
			   to: CGPoint(x: position2.x - 40, y: position2.y ),
			   control: CGPoint(x: -5, y: 100))
}
