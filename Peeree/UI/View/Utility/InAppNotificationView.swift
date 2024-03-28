//
//  InAppNotificationView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

struct InAppNotificationView: View {
	let notification: InAppNotification

	let time: TimeInterval

	@State private var secondsRemaining: Int = -1

	@State private var expanded = false

	private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

	private var backgroundColor: Color {
		switch self.notification.severity {
		case .info:
			Color.blue
		case .warning:
			Color.orange
		case .error:
			Color.red
		}
	}

	var body: some View {
		VStack {
			Text(notification.localizedTitle)
				.font(.title3)
				.lineLimit(1)
			Text(notification.localizedMessage)
				.font(.body)
				.lineLimit(expanded ? 3 : 1)
			Text(notification.furtherDescription ?? "")
				.font(.caption)
				.lineLimit(expanded ? 6 : 1)
		}
		.frame(maxWidth: .infinity)
		.padding()
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
		.background(RoundedRectangle(cornerRadius: 12)
			.fill(self.backgroundColor).opacity(0.3))
		.overlay(alignment: .topTrailing) {
			Text("\(self.secondsRemaining)")
				.font(.caption2)
				.padding(4)
				.background(Circle().fill(Color("ColorBackground")))
				.padding(4)
				.padding(.trailing, 2)
				.onReceive(timer) { _ in
					if secondsRemaining < 0 {
						secondsRemaining = Int(time)
					} else if secondsRemaining == 0 {
						timer.upstream.connect().cancel()
					} else {
						secondsRemaining -= 1
					}
				}
		}
		.onTapGesture {
			withAnimation {
				self.expanded.toggle()
			}
		}

	}
}

#Preview {
	InAppNotificationView(notification: InAppNotification(localizedTitle: "A Title", localizedMessage: "A descriptive text.", severity: .info, furtherDescription: "Some more context."), time: 5.0)
}
