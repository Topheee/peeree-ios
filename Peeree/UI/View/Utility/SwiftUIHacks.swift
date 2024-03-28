//
//  SwiftUIHacks.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

extension View {
	// https://blog.overdesigned.net/posts/2020-09-23-swiftui-availability/
	func modify<T: View>(@ViewBuilder _ modifier: (Self) -> T) -> some View {
		return modifier(self)
	}

	// https://fivestars.blog/swiftui/conditional-modifiers.html
	@ViewBuilder
	func `if`<Transform: View>(_ condition: Bool,
							   transform: (Self) -> Transform) -> some View {
		if condition {
			transform(self)
		} else {
			self
		}
	}
}

func advancing(_ i: inout Int, by: Int = 1) -> Int {
	i += by
	return i
}

extension Animation {
	// https://developer.apple.com/tutorials/swiftui/animating-views-and-transitions#Customize-view-transitions
	static func ripple(index: Int) -> Animation {
		Animation.spring(dampingFraction: 0.9)
			.speed(2)
			.delay(0.06 * Double(index))
	}
}

// http://stackoverflow.com/questions/57257704/ddg#58531033
extension Color {

	func uiColor() -> UIColor {

		let components = self.components()
		return UIColor(red: components.r, green: components.g, blue: components.b, alpha: components.a)
	}

	private func components() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {

		let scanner = Scanner(string: self.description.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
		var hexNumber: UInt64 = 0
		var r: CGFloat = 0.0, g: CGFloat = 0.0, b: CGFloat = 0.0, a: CGFloat = 0.0

		let result = scanner.scanHexInt64(&hexNumber)
		if result {
			r = CGFloat((hexNumber & 0xff000000) >> 24) / 255
			g = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255
			b = CGFloat((hexNumber & 0x0000ff00) >> 8)  / 255
			a = CGFloat( hexNumber & 0x000000ff)        / 255
		}
		return (r, g, b, a)
	}
}
