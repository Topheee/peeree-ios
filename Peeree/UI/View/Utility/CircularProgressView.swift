//
//  CircularProgressView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

// https://sarunw.com/posts/swiftui-circular-progress-bar/
struct CircularProgressView: View {
	@Binding var progress: Double

	private let thickness: CGFloat = 8

	@State private var wobberAnimation: CGFloat = 1.0

	var body: some View {
		ZStack {
			Circle()
				.stroke(
					Color("ColorDivider"),
					lineWidth: thickness
				)
			Circle()
				.trim(from: 0, to: progress)
				.stroke(
					LinearGradient(colors: [Color.accentColor, Color.blue], startPoint: UnitPoint(), endPoint: UnitPoint(x: wobberAnimation, y: wobberAnimation)),
					style: StrokeStyle(
						lineWidth: thickness,
						lineCap: .round
					)
				)
				.rotationEffect(.degrees(-90))
				.animation(.easeOut, value: progress)
		}
		.onAppear {
			withAnimation(.easeInOut(duration: 3.0).repeatForever()) {
				wobberAnimation = 0.5
			}
		}
	}
}

#Preview {
	return CircularProgressView(progress: Binding.constant(0.9))
}
