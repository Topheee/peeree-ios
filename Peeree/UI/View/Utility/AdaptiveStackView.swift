//
//  AdaptiveStackView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

// https://www.hackingwithswift.com/quick-start/swiftui/how-to-automatically-switch-between-hstack-and-vstack-based-on-size-class
struct AdaptiveStackView<Content: View>: View {
	@State private var orientation: UIAxis
	let horizontalAlignment: HorizontalAlignment
	let verticalAlignment: VerticalAlignment
	let spacing: CGFloat?
	let content: () -> Content

	init(orientation: UIAxis, horizontalAlignment: HorizontalAlignment = .center, verticalAlignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
		self.horizontalAlignment = horizontalAlignment
		self.verticalAlignment = verticalAlignment
		self.spacing = spacing
		self.content = content
		self.orientation = orientation
	}

	var body: some View {
		Group {
			if orientation == .vertical {
				VStack(alignment: horizontalAlignment, spacing: spacing, content: content)
			} else {
				HStack(alignment: verticalAlignment, spacing: spacing, content: content)
			}
		}
	}
}

#Preview {
	AdaptiveStackView(orientation: .vertical) {
		Text("Hello, World!")
	}
}
