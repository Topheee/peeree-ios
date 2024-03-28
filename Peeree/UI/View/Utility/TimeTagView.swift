//
//  TimeTagView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

struct TimeTagView: View {
	let text: String

	@State private var labelHeight = CGFloat.zero

	var body: some View {
		HStack {
			Image(systemName: "clock.fill")
				.frame(maxHeight: labelHeight)
			Text(text)
				.padding(.trailing, 6)
				.overlay(
					GeometryReader(content: { geometry in
						Color.clear
							.onAppear(perform: {
								self.labelHeight = geometry.frame(in: .local).size.height
							})
					})
				)
		}
		.padding(4)
		.background(RoundedRectangle(cornerRadius: 15).fill(Color.accentColor))
	}
}

#Preview {
	TimeTagView(text: "Hello, World!")
}
