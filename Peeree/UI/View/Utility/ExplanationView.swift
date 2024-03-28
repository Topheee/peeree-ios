//
//  ExplanationView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

struct Explanation: Identifiable {
	var iconName: String

	var title: LocalizedStringKey

	var content: LocalizedStringKey

	var id: String { return iconName }
}

struct ExplanationView: View {
	let explanations: [Explanation]

	var body: some View {
		ZStack(alignment: .top) {
			ScrollView {
				VStack(alignment: .leading) {
					ForEach(explanations) { explanation in
						HStack {
							Image(explanation.iconName)
								.resizable()
								.aspectRatio(contentMode: .fit)
								.frame(height: 52)

							Text(explanation.title)
								.font(.title3)
						}

						Text(explanation.content)
							.font(.body)
							.padding(.horizontal)
							.padding(.bottom)
					}
				}
				.padding()
				.padding(.top, 100)
			}

			HStack {
				ForEach(explanations) { explanation in
					Image(explanation.iconName)
						.resizable()
						.aspectRatio(contentMode: .fit)
				}
			}
			.frame(maxWidth: .infinity)
			.frame(height: 100)
			.background(.regularMaterial)
		}
	}
}

#Preview {
	let explanations: [Explanation] = [
		Explanation(iconName: "BatteryColored", title: "Battery", content: "Lorem ipsum dolor. adsf adfads fdaf ads fasdf adsf asdf adsfasd fads faf sdadsf afds asdf "),
		Explanation(iconName: "ConnectedColored", title: "Connected", content: "Lorem ipsum dolor."),
		Explanation(iconName: "ClockColored", title: "Clock", content: "Lorem ipsum dolor.")
	]

	return ExplanationView(explanations: explanations)
}
