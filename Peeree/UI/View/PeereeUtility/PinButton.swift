//
//  PinButton.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeServer

struct PinButtonStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.padding()
			.background(Color.accentColor)
			.modify {
				if #available(iOS 15, *) {
					$0.foregroundStyle(.white)
				} else { $0 }
			}
			.clipShape(Capsule())
			.scaleEffect(configuration.isPressed ? 0.9 : 1)
			.transformEffect(configuration.isPressed ? .init(translationX: 0, y: 2) : .identity)
			.animation(.easeOut(duration: 0.2), value: configuration.isPressed)
	}
}

struct PinButton: View {
	let pinState: PinState

	let font: Font

	let action: () -> Void

	var body: some View {
		Button(action: action) {
			HStack {
				Image(self.pinState.isPinnedOrUnpinning ? "PinTemplateFilled" : "PinTemplate")
					.resizable()
					.aspectRatio(contentMode: .fit)

				if pinState == .pinMatch {
					Text("Pin Match!")
						.font(font)
				}
			}
		}
		.frame(maxHeight: 72)
		.buttonStyle(PinButtonStyle())
//		.shadow(radius: self.pinState == .pinMatch ? 10 : 0)
		.disabled(self.pinState.isTransitioning)
	}
}

#Preview {
	PinButton(pinState: .unpinned, font: .title) {}
}

#Preview {
	PinButton(pinState: .pinned, font: .title) {}
}

#Preview {
	PinButton(pinState: .pinMatch, font: .title) {}
}

