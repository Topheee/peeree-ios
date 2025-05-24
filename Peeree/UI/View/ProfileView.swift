//
//  ProfileView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI
import PhotosUI

import PeereeCore
import PeereeDiscovery

struct ProfileView: View {

	let doneAction: () -> Void

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass

	@EnvironmentObject private var socialViewState: SocialViewState

	@EnvironmentObject private var discoveryViewState: DiscoveryViewState

	@State private var showBirthdayPicker: Bool = false

	@State private var showImagePicker: Bool = false

	/// This is a workaround to the problem that directly referencing discoveryViewState.profile.image did not update the view.
	@State private var profileImage = Image("PortraitPlaceholder")

	private let dateRange: ClosedRange<Date> = {
		let calendar = Calendar.current
		let today = Date()
		let thisYear = calendar.component(.year, from: today)
		let thisMonth = calendar.component(.month, from: today)
		let thisDay = calendar.component(.day, from: today)
		let startComponents = DateComponents(year: thisYear-PeerInfo.MaxAge, month: thisMonth, day: thisDay)
		let endComponents = DateComponents(year: thisYear-PeerInfo.MinAge, month: thisMonth, day: thisDay)
		return (calendar.date(from:startComponents) ?? today)
			...
			(calendar.date(from:endComponents) ?? today)
	}()

	var body: some View {
		NavigationView {
			VStack(alignment: .center) {
				Form {
					VStack {
						TextField(text: $discoveryViewState.profile.info.nickname, prompt: Text("Name")) {

						}
						.textInputAutocapitalization(.words)
						.disableAutocorrection(true)
						.textFieldStyle(.roundedBorder)
						.padding(.top, 12)

						profileImage
							.resizable()
							.aspectRatio(contentMode: .fit)
							.clipShape(Circle())
							.onTapGesture {
								withAnimation {
									self.showImagePicker.toggle()
								}
							}
							.sheet(isPresented: $showImagePicker) {
								ImagePicker { picked(image: $0) }
							}
					}

					VStack {
						Toggle("Show Age on Profile", isOn: $showBirthdayPicker)

						if showBirthdayPicker {
							// https://stackoverflow.com/questions/59272801/swiftui-datepicker-binding-optional-date-valid-nil#59274498
							DatePicker("Birthday", selection: $discoveryViewState.profile.uiBirthday, in: dateRange, displayedComponents: [.date])
								.padding(.top)
						}
					}

					Picker("Gender", selection: $discoveryViewState.profile.info.gender) {
						Text("Male").tag(PeerInfo.Gender.male)
						Text("Female").tag(PeerInfo.Gender.female)
						Text("Queer").tag(PeerInfo.Gender.queer)
					}

					VStack(alignment: .leading) {
						Text("Biography:")
							.padding(.top)
						TextEditor(text: $discoveryViewState.profile.biography)
							.background(RoundedRectangle(cornerRadius: 5).fill(Color("ColorDivider")))
							.frame(minHeight: 32)
							.padding(.bottom)
					}
				}

				AccountView()
			}
			.background(.regularMaterial)
			.overlay(alignment: .top) {
				InAppNotificationStackView(controller: InAppNotificationStackViewState.shared)
					.padding()
			}
			.navigationBarTitle("Profile")
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					NavigationLink {
						PersonView(socialPersona: socialViewState.userSocialPersona, discoveryPersona: discoveryViewState.profile)
					} label: {
						Text("Preview")
					}
					.isDetailLink(true)
				}

				ToolbarItem(placement: .navigationBarLeading) {
					Button {
						doneAction()
					} label: {
						Label("Done", systemImage: "checkmark.circle")
					}
				}
			}
			.onAppear {
				showBirthdayPicker = discoveryViewState.profile.birthday != nil
				profileImage = discoveryViewState.profile.image
			}
			.onDisappear {
				if !showBirthdayPicker {
					discoveryViewState.profile.birthday = nil
				}
			}
		}
	}

	private func picked(image: UIImage) {
		discoveryViewState.profile.picture = image
		// gosh this is so fucking ugly
		profileImage = Image(image.cgImage!, scale: 1.0, label: Text("A person."))
	}
}

#Preview {
	let ds = DiscoveryViewState()
	let ss = SocialViewState()
	return ProfileView() {}
		.environmentObject(ds)
		.environmentObject(ss)
}
