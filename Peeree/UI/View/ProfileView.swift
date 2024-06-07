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
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	@EnvironmentObject private var socialViewState: SocialViewState

	@EnvironmentObject private var discoveryViewState: DiscoveryViewState

	@State private var showBirthdayPicker: Bool = false

	@State private var showImagePicker: Bool = false

	@State private var showCreateDeleteAccountDialog = false

	private var mainWebsite: URL {
		return URL(string: NSLocalizedString("https://www.peeree.de/en/index.html", comment: "Peeree Homepage")) ?? URL(fileURLWithPath: "/")
	}

	private var privacyWebsite: URL {
		return URL(string: NSLocalizedString("https://www.peeree.de/en/privacy.html", comment: "Peeree Privacy Policy")) ?? URL(fileURLWithPath: "/")
	}

	private var termsWebsite: URL {
		return URL(string: NSLocalizedString("terms-app-url", comment: "Peeree App Terms of Use URL")) ?? URL(fileURLWithPath: "/")
	}

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

						discoveryViewState.profile.image
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

				VStack {
					VStack {
						Text(socialViewState.userPeerID?.uuidString ?? "No identity.")
							.font(.caption)
							.fontWeight(.light)
							.modify {
								if #available(iOS 16, *) {
									$0.italic(!socialViewState.accountExists.isOn)
								} else {
									if !socialViewState.accountExists.isOn {
										$0.italic()
									}
								}
							}
							.padding(.top, 0.5)

						Button(role: socialViewState.accountExists.isOn ? .destructive : .none) {
							showCreateDeleteAccountDialog.toggle()
						} label: {
							Text(socialViewState.accountExistsText)
								.modify {
									if #available(iOS 16, *) {
										$0.bold(!socialViewState.accountExists.isOn)
									} else {
										if !socialViewState.accountExists.isOn {
											$0.bold()
										} else {
											$0
										}
									}
								}
						}
						.disabled(socialViewState.accountExists.isTransitioning)
						.modify {
							if #available(iOS 15, *) {
								if socialViewState.accountExists.isOn {
									$0.confirmationDialog(
										"Delete Identity",
										isPresented: $showCreateDeleteAccountDialog
									) {
										Button("Delete Identity", role: .destructive) {
											socialViewState.delegate?.deleteIdentity()
										}
										Button("Cancel", role: .cancel) {}
									} message: {
										Text("This will delete your global Peeree identity and cannot be undone. All your pins as well as pins on you will be lost.")
									}
								} else {
									$0.confirmationDialog(
										"Create Identity",
										isPresented: $showCreateDeleteAccountDialog
									) {
										Button("Create Identity") {
											socialViewState.delegate?.createIdentity()
										}
										Button("View Terms") { openTerms() }
										Button("Cancel", role: .cancel) {}
									} message: {
										Text(String(format: NSLocalizedString("By tapping on '%@', you agree to our Terms of Use.", comment: "Message in identity creation alert."), NSLocalizedString("Create Identity", comment: "Caption of button")))
									}
								}
							} else {
								if socialViewState.accountExists.isOn {
									$0.actionSheet(isPresented: $showCreateDeleteAccountDialog) {
										ActionSheet(title: Text("Delete Identity"),
													message: Text("This will delete your global Peeree identity and cannot be undone. All your pins as well as pins on you will be lost."),
													buttons: [
														.cancel(),
														.destructive(
															Text("Delete Identity")) {
																socialViewState.delegate?.deleteIdentity()
															}])
									}
								} else {
									$0.actionSheet(isPresented: $showCreateDeleteAccountDialog) {
										ActionSheet(title: Text("Create Identity"),
													message: Text(String(format: NSLocalizedString("By tapping on '%@', you agree to our Terms of Use.", comment: "Message in identity creation alert."), NSLocalizedString("Create Identity", comment: "Caption of button"))),
													buttons: [
														.cancel(),
														.default(Text("View Terms")) { openTerms() },
														.destructive(
															Text("Create Identity")) {
																socialViewState.delegate?.createIdentity()
															}])
									}
								}
							}
						}
						
						HStack(spacing: 24.0) {
						 if #available(iOS 14, *) {
							 Link("Website", destination: mainWebsite)
							 Link("Privacy Policy", destination: privacyWebsite)
						 } else {
							 Button() {
								 UIApplication.shared.open(mainWebsite)
							 } label: {
								 Text("Website")
							 }
							 Button() {
								 UIApplication.shared.open(privacyWebsite)
							 } label: {
								 Text("Privacy Policy")
							 }
						 }
					 }
					}
				}
				.modify {
					if verticalSizeClass == .regular {
						$0.padding(.top).padding(.bottom)
					} else { $0 }
				}
			}
			.background(.regularMaterial)
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
			}
			.onDisappear {
				if !showBirthdayPicker {
					discoveryViewState.profile.birthday = nil
				}
			}
		}
	}

	private func openTerms() {
		let website = self.termsWebsite
		DispatchQueue.main.async {
			UIApplication.shared.open(website)
		}
	}

	private func picked(image: UIImage) {
		discoveryViewState.profile.picture = image
	}
}

#Preview {
	return ProfileView() {}
}
