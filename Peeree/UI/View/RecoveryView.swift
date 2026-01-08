//
//  RecoveryView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 23.05.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

import SwiftUI

/// Configuration of the `RecoveryView`.
enum RecoveryViewMode {
	/// The user has pressed the 'Recover Account' Button
	typealias RecoverAction = (String) -> Void

	/// The 'display' mode, i.e. read-only.
	case presenting

	/// The 'querying' mode, i.e. letting the user entry the recovery code.
	case recovering(RecoverAction)
}

struct RecoveryView: View {

	/// Central configuration of this view.
	let mode: RecoveryViewMode

	/// True if the user is asked to enter their code.
	var entry: Bool {
		if case .presenting = self.mode {
			return false
		} else {
			return true
		}
	}

	/// Matrix for `columnCount` depending on UI state.
	///
	/// Dimensions:
	/// 1. DynamicTypeSize.isAccessibilitySize
	/// 2. UserInterfaceSizeClass (0: regular, 1: compact)
	private let columnCounts = [
		[6, 16], [7, 12]
	]

	/// The number of rows in the recovery code letter grid.
	var columnCount: Int {
		let dim0 = self.dynamicTypeSize.isAccessibilitySize ? 1 : 0
		let dim1 = self.verticalSizeClass == .compact ? 1 : 0

		return self.columnCounts[dim0][dim1]
	}

	/// Matrix for `letterPadding` depending on UI state.
	///
	/// Dimensions:
	/// 1. DynamicTypeSize.isAccessibilitySize
	/// 2. UserInterfaceSizeClass (0: regular, 1: compact)
	private let letterPaddings: [[CGFloat]] = [
		[6, 1], [2, 1]
	]

	/// The number of rows in the recovery code letter grid.
	var letterPadding: CGFloat {
		let dim0 = self.dynamicTypeSize.isAccessibilitySize ? 1 : 0
		let dim1 = self.verticalSizeClass == .compact ? 1 : 0

		return self.letterPaddings[dim0][dim1]
	}

	@Binding var letters: [String]

	/// Whether all fields contain a letter.
	var filled: Bool {
		(self.letters.reduce(0, { partialResult, element in
			return partialResult + element.count
		}) == self.letters.count)
	}

	var body: some View {
		Text("Account Recovery")
			.font(.title)

		if self.verticalSizeClass != .compact {
			Text(entry ? "Enter your recovery phrase." : "Your secret recovery phrase.")
				.font(.caption)
		}

		if !self.dynamicTypeSize.isAccessibilitySize {
			Text(entry ? "This will log you out on any other device." : "It is not possible to view this code again.")
				.italic()
				.padding(self.verticalSizeClass != .compact ? 8 : 4)
		}

		VStack {
			VStack {
				ForEach(0..<letters.count / self.columnCount, id: \.self) { row in
					HStack {
						ForEach((row * self.columnCount)..<(row * self.columnCount) + self.columnCount, id: \.self) { column in
							TextField(text: $letters[column]) { Text("0") }
								.focused($letterFocus, equals: column)
								.frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 52 : 28)
								.padding(self.letterPadding)
						}
					}
				}

				HStack {
					ForEach(0..<letters.count % self.columnCount, id: \.self) { column in
						TextField(text: $letters[letters.count - (letters.count % self.columnCount) + column]) { Text("0") }
							.focused($letterFocus, equals: letters.count - (letters.count % self.columnCount) + column)
							.frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 52 : 28)
							.padding(self.letterPadding)
					}
				}
			}
			.keyboardType(.asciiCapable)
			.lineLimit(1)
			.disabled(!entry)
			.multilineTextAlignment(.center)
			.textInputAutocapitalization(.characters)
			.disableAutocorrection(true)
			.textFieldStyle(.roundedBorder)

			if #available(iOS 16.0, *), self.entry {
				PasteButton(payloadType: String.self) { paste in
					paste.first.map { self.fillIn(text: $0) }
				}
			}

			AdaptiveStackView(orientation: verticalSizeClass == .compact ? .horizontal : .vertical) {
				Button(entry ? "Recover Account" : "Save Code", role: .none) {
					self.showActionDialog.toggle()
				}
				.buttonStyle(.borderedProminent)
				.disabled(!self.filled)
				.confirmationDialog(
					self.entry ? "Recover Account" : "Save Code",
					isPresented: $showActionDialog
				) {
					if self.entry {
						Button("Recover Account") {
							self.actionRecover()
						}
					} else {
						Button("Share") {
							self.showShare.toggle()
						}
						Button("Copy to Clipboard") {
							self.actionCopyToClipboard()
						}
						Button("Save in iCloud") {
							self.actionSaveInCloud()
						}
					}
				} message: {
					Text(self.entry ? "Recovering your account overrides all data, except for your profile." : "Export code for save storage.")
				}
				.sheet(isPresented: $showShare) {
					ActivityViewController(configuration: self.shareConfiguration())
				}
			}
			.padding(.top, 8)

			Text(self.showSavedToCloud ? "Saved to iCloud." : "")
				.font(.caption)
		}
		.padding()
		.background(Color("ColorDivider"))
		.border(Color("ColorDivider"), width: 5.0)
		.cornerRadius(20.0)
		.shadow(radius: 5.0)
		.onChange(of: self.letters) { _ in
			self.distributeLetters()
			if let l = self.letterFocus {
				self.letterFocus = l + 1
			}
		}
		.onAppear {
			if self.entry {
				// Always pre-fill with data from cloud.
				self.actionLoadFromCloud()
			}
		}

		Text(entry ? "Type or paste your code." : "Store your code in a secure and durable location, e.g. a password manager.")
			.font(.footnote)
			.padding(.top, 2)
	}

	/// The username of the stored credential.
	private static let CredentialUser = "API"

	private var protectionSpace: URLProtectionSpace {
		URLProtectionSpace(
			host: "api.peeree.de", port: 443, protocol: "https",
			realm: nil, authenticationMethod: nil)
	}

	@State private var showActionDialog = false

	@State private var showShare: Bool = false

	@State private var showSavedToCloud: Bool = false

	@FocusState private var letterFocus: Int?

	@Environment(\.dynamicTypeSize) private var dynamicTypeSize: DynamicTypeSize

	@Environment(\.verticalSizeClass) private var verticalSizeClass

	/// Splits up `text` and fills it into the TextFields.
	private func fillIn(text: String) {
		let validChars = text.unicodeScalars.filter { scalar in
			scalar.properties.isASCIIHexDigit || scalar == "-"
		}
		.map { String($0) }

		self.letters.replaceSubrange(
			0..<min(validChars.endIndex, self.letters.endIndex),
			with: validChars)
	}

		/// Make sure that each element in `letters` is just one character long.
	 private func distributeLetters() {
		for i in 0..<self.letters.count {
			let s = self.letters[i].unicodeScalars

			guard s.count > 1 else { continue }

			let first = String(s[s.startIndex])
			let remainder = s[s.index(after: s.startIndex)...]

			self.letters[i] = first

			if i < self.letters.count - 1 {
				self.letters[i + 1] += String(remainder)
			}
		}
	}

	/// Initiate account recovery.
	private func actionRecover() {
		guard case let .recovering(action) = self.mode else { return }

		action(self.recoveryCode)
	}

	/// The patched-together recovery code.
	private var recoveryCode: String {
		return self.letters.joined()
	}

		/// Configuration for the system's share sheet.
	 private func shareConfiguration() -> UIActivityItemsConfiguration {
		let itemProvider = NSItemProvider(
			item: self.recoveryCode as NSString,
			typeIdentifier: "public.utf8-plain-text")

		let configuration =
		UIActivityItemsConfiguration(itemProviders: [itemProvider])

		// Don't allow collaboration.
		configuration.perItemMetadataProvider = { _, key in
			if #available(iOS 18.0, *) {
				switch key {
				case .collaborationModeRestrictions:
					let modeRestriction = UIActivityViewController
						.CollaborationModeRestriction(
						disabledMode: .collaborate
					)
					return [modeRestriction]
				default:
					return nil
				}
			} else {
				return nil
			}
		}

		return configuration
	}

	private func actionCopyToClipboard() {
		UIPasteboard.general.string = self.recoveryCode
	}

	/// Persists the recovery code in the cloud.
	private func actionSaveInCloud() {
		// test: I don't think this URLCredentialStorage is accessible from the passwords app.
		let credential = URLCredential(
			user: Self.CredentialUser, password: self.recoveryCode,
			persistence: .synchronizable)

		let storage = URLCredentialStorage.shared

		storage.setDefaultCredential(
			credential, for: self.protectionSpace)

		self.showSavedToCloud = true
	}

	/// Loads the recovery code from the cloud; if any.
	private func actionLoadFromCloud() {
		guard let credential = URLCredentialStorage.shared
			.defaultCredential(for: self.protectionSpace),
			  let password = credential.password else {
			return
		}

		self.fillIn(text: password)
	}
}

#Preview {
	RecoveryView(mode: .presenting, letters: Binding.constant(
		Array<String>(repeating: "", count: 32)))
}

#Preview {
	RecoveryView(mode: .recovering({ code in
	}), letters: Binding.constant(
		"B117D2A8-4446-4268-9764-3B2BDD1153F7".unicodeScalars.map {
			String($0)
		}))
}
