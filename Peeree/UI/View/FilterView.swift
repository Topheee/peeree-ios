//
//  FilterView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeDiscovery

struct FilterView: View {

	@Binding var filter: BrowseFilter

	let doneAction: () -> Void

	@State private var toggleWidth = CGFloat.zero

	@State private var ageMinRange: ClosedRange<Float> = Float(PeerInfo.MinAge)...Float(PeerInfo.MaxAge)

	@State private var ageMaxRange: ClosedRange<Float> = Float(PeerInfo.MinAge)...Float(PeerInfo.MaxAge)

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	var body: some View {
		NavigationView {
			Form {
				Section(header: Text("Gender"), footer: Text("Filter based on gender.")) {
					HStack(alignment: .center) {
						Toggle("Males", isOn: $filter.allowMales)
							.modify {
								if #available(iOS 15, *) {
									$0.toggleStyle(.button)
								}
							}
							.frame(minWidth: self.toggleWidth)
							.overlay(
								GeometryReader(content: { geometry in
									Color.clear
										.onAppear(perform: {
											self.toggleWidth = max(geometry.frame(in: .local).size.width, self.toggleWidth)
										})
								})
							)
						Toggle("Queers", isOn: $filter.allowQueers)
							.modify {
								if #available(iOS 15, *) {
									$0.toggleStyle(.button)
								}
							}
							.frame(minWidth: self.toggleWidth)
							.overlay(
								GeometryReader(content: { geometry in
									Color.clear
										.onAppear(perform: {
											self.toggleWidth = max(geometry.frame(in: .local).size.width, self.toggleWidth)
										})
								})
							)
						Toggle("Females", isOn: $filter.allowFemales)
							.modify {
								if #available(iOS 15, *) {
									$0.toggleStyle(.button)
								}
							}
							.frame(minWidth: self.toggleWidth)
							.overlay(
								GeometryReader(content: { geometry in
									Color.clear
										.onAppear(perform: {
											self.toggleWidth = max(geometry.frame(in: .local).size.width, self.toggleWidth)
										})
								})
							)
					}
					.frame(maxWidth: .infinity)
				}

				Section(header: Text("Age"), footer: Text("Filter based on age.")) {
					VStack {
						Slider(value: $filter.ageMin, in: ageMinRange) { isEditing in
							if !isEditing {
								ageMaxRange = self.filter.ageMin...Float(PeerInfo.MaxAge)
								UISelectionFeedbackGenerator().selectionChanged()
							}
						}
						HStack {
							Text("Minimum Age:")
							TextField("Minimum Age", value: $filter.ageMin, formatter: NumberFormatter())
								.disabled(true)
								.frame(maxWidth: 36)
						}
					}
					VStack {
						Slider(value: $filter.ageMax, in: ageMaxRange) { isEditing in
							if !isEditing {
								ageMinRange = Float(PeerInfo.MinAge)...self.filter.ageMax
								UISelectionFeedbackGenerator().selectionChanged()
							}
						}
						HStack {
							Text("Maximum Age:")
							TextField("Maximum Age", value: $filter.ageMax, formatter: NumberFormatter())
								.disabled(true)
								.frame(maxWidth: 36)
						}
					}
					Toggle(isOn: $filter.onlyWithAge) { Text("Only with age available") }
				}

				Section(header: Text("Portrait"), footer: Text("Filter based on portrait.")) {
					Toggle(isOn: $filter.onlyWithPicture) { Text("Only with picture available") }
				}

				Section(header: Text("Filter"), footer: Text("Display people although they are filtered out. Notifications are still not triggered.")) {
					Toggle("Display filtered people", isOn: $filter.displayFilteredPeople)
				}
			}
			.navigationTitle("Filter")
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					Button {
						doneAction()
					} label: {
						Label("Done", systemImage: "checkmark.circle")
					}
				}
			}
		}
	}
}

#Preview {
	FilterView(filter: .constant(BrowseFilter())) {}
}
