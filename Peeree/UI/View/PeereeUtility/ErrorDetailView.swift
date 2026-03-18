//
//  ErrorDetailView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 08.03.26.
//  Copyright © 2026 Kobusch. All rights reserved.
//


import SwiftUI

import PeereeCore
import PeereeDiscovery

struct ErrorDetailView: View {

	let displayedError: AudiencedError

	@Binding var shareErrorReports: Bool

	@State private var expanded = false

	@State private var reportSent = false

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	var body: some View {
		ScrollView(.vertical) {
			HStack {
				Text(Image(systemName: "exclamationmark.triangle"))
				 .font(.title2)

				Text("Houston, we have a problem.")
				 .font(.title2)
			}

			let intro: LocalizedStringKey =
			switch self.displayedError.source {
			case .user:
				"Try to fix the issue by following these instructions:"
			case .consumer:
				"We seem to have made a mistake. Please share this information with us:"
			case .vendor:
				"Mistakes were made. Please share this information with us:"
			case .external:
				"The error might be temporary, so try again later."
			}

			Text(intro).font(.callout)

			if self.displayedError.source == .user {
				Text(displayedError.localizedDescription)
					.font(.body)

				if let cause = self.displayedError.cause {
					Toggle("Display Technical details (English)", isOn: $expanded)

					Text(self.expanded ? cause.localizedDescription : "")
						.font(.body)
				}

				Text("Can't fix it? Share with us.").font(.body)
			} else {
				Toggle("Display Shared Information (English)", isOn: $expanded)

				Text(self.expanded ? self.displayedError.technicalReport : "")
					.font(.body)

				Toggle(
					"Share error information with Peeree",
					isOn: self.$shareErrorReports)
			}

			if !self.shareErrorReports || self.displayedError.source == .user {
				Button {
					sendReport()
				} label: {
					Label("Share this time", systemImage: "paperplane.fill")
						.labelStyle(.iconOnly)
						.font(.title)
				}
			}
		}
	}

	private func sendReport() {
		// TODO: implement
	}
}

#Preview {
	ErrorDetailView(
		displayedError: AudiencedError(
			source: .user, domain: "Domain", message: "Lorem ipsum dolor"),
		shareErrorReports: .constant(false))
}

#Preview {
	ErrorDetailView(
		displayedError: AudiencedError(
			source: .external, domain: "Domain", message: "Lorem ipsum dolor"),
		shareErrorReports: .constant(true))
}
