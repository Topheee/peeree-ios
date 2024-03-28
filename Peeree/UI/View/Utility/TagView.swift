//
//  TagView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

struct TagView: View {
	let text: String

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	@State private var labelHeight = CGFloat.zero

	@State private var labelWidth = CGFloat.zero

	@State private var hasTimeElapsed = false

	var body: some View {
		HStack {
			Circle()
				.fill(Color.white)
				.padding(.vertical, 2)
				.padding(.leading, 2)
				.frame(maxHeight: labelHeight)

			Text(text)
				.padding(.trailing, 6)
				.overlay(
					GeometryReader { geometry in
						Color.clear
						.onAppear {
							self.labelHeight = geometry.frame(in: .local).size.height
							self.labelWidth = geometry.frame(in: .local).size.width
						}
					}
				)
				.modify {
					if #available(iOS 15, *) {
						$0.overlay {
							HStack {
								Spacer()
								Rectangle()
									.fill(Color.accentColor)
									.frame(width: hasTimeElapsed ? 0.0 : labelWidth)
									.animation(reduceMotion ? .none : .easeOut(duration: 0.8), value: hasTimeElapsed)
							}
							.padding(.leading, -12)
						}
					}
				}
				.onAppear(perform: delayText)
		}
		.padding(4)
		.background(RoundedRectangle(cornerRadius: 15).fill(Color.accentColor))
	}

	private func delayText() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
			hasTimeElapsed = true
		}
	}
}

#Preview {
	return TagView(text: "Hello, World!")
}
