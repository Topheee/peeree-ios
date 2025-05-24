//
//  AccountView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 24.05.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

import SwiftUI

struct AccountView: View {

	var body: some View {
		VStack {
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
			.confirmationDialog(
				socialViewState.accountExists.isOn ? "Delete Identity" : "Create Identity",
				isPresented: $showCreateDeleteAccountDialog
			) {
				if socialViewState.accountExists.isOn {
					Button("Delete Identity", role: .destructive) {
						socialViewState.delegate?.deleteIdentity()
					}
				} else {
					Button("Create Identity") {
						socialViewState.delegate?.createIdentity()
					}
					Button("View Terms") { self.openTerms() }
				}
			} message: {
				Text(socialViewState.accountExists.isOn ?
					 "This will delete your global Peeree identity and cannot be undone. All your pins as well as pins on you will be lost."
					 :
						String(format: NSLocalizedString("By tapping on '%@', you agree to our Terms of Use.", comment: "Message in identity creation alert."), NSLocalizedString("Create Identity", comment: "Caption of button")))
			}

			Text(socialViewState.userPeerID?.uuidString ?? NSLocalizedString("No identity.", comment: "Placeholder for PeerID"))
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
				.padding(.bottom, 0.5)

			HStack(spacing: 24.0) {
				Link("Website", destination: mainWebsite)
				Link("Privacy Policy", destination: privacyWebsite)
			}
		}
		.modify {
			if verticalSizeClass == .regular {
				$0.padding(.top).padding(.bottom)
			} else { $0 }
		}
	}

	// MARK: - Private

	@EnvironmentObject private var socialViewState: SocialViewState

	@State private var showCreateDeleteAccountDialog = false

	@Environment(\.verticalSizeClass) private var verticalSizeClass

	private var mainWebsite: URL {
		return URL(string: NSLocalizedString("https://www.peeree.de/en/index.html", comment: "Peeree Homepage")) ?? URL(fileURLWithPath: "/")
	}

	private var privacyWebsite: URL {
		return URL(string: NSLocalizedString("https://www.peeree.de/en/privacy.html", comment: "Peeree Privacy Policy")) ?? URL(fileURLWithPath: "/")
	}

	private var termsWebsite: URL {
		return URL(string: NSLocalizedString("terms-app-url", comment: "Peeree App Terms of Use URL")) ?? URL(fileURLWithPath: "/")
	}


	private func openTerms() {
		let website = self.termsWebsite
		Task { @MainActor in
			UIApplication.shared.open(website)
		}
	}
}

#Preview {
	let ss = SocialViewState()
	ss.accountExists = .on
	return AccountView()
		.environmentObject(ss)
}

#Preview {
	let ss = SocialViewState()
	ss.accountExists = .off
	return AccountView()
		.environmentObject(ss)
}

