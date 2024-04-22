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

	@State private var expanded = false

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
		.onTapGesture {
			withAnimation {
				self.expanded.toggle()
			}
		}

	}
}

#Preview {
	InAppNotificationView(notification: InAppNotification(localizedTitle: "A Title", localizedMessage: "A descriptive text.", severity: .info, furtherDescription: "Some more context."))
}
