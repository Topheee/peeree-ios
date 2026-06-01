//
//  PhotoPickerWrapper.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI
import PhotosUI

// https://stackoverflow.com/questions/57110290/how-to-pick-image-from-gallery-in-swiftui
struct ImagePicker: UIViewControllerRepresentable {

	@Environment(\.presentationMode)
	var presentationMode

	let selectionFinishedAction: @Sendable @MainActor (Result<UIImage, Error>) -> Void

	final class Coordinator:
		NSObject, UINavigationControllerDelegate,
		PHPickerViewControllerDelegate
	{

		@Binding var presentationMode: PresentationMode

		let selectionFinishedAction: @Sendable @MainActor (Result<UIImage, Error>) -> Void

		init(
			presentationMode: Binding<PresentationMode>,
			selectionFinishedAction: @Sendable @MainActor @escaping (Result<UIImage, Error>) -> Void
		) {
			self._presentationMode = presentationMode
			self.selectionFinishedAction = selectionFinishedAction
		}

		func picker(
			_ picker: PHPickerViewController,
			didFinishPicking results: [PHPickerResult]
		) {
			defer {
				self.presentationMode.dismiss()
			}

			guard let itemProvider = results.first?.itemProvider else { return }

			let a = self.selectionFinishedAction

			if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
				itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in

					let result: Result<UIImage, Error>

					if let error {
						result = .failure(error)
					} else if let data, let uiImage = UIImage(data: data) {
						result = .success(uiImage)
					} else {
						result = .failure(PHPhotosError(.internalError))
					}

					Task { @MainActor in
						a(result)
					}
				}
			}
		}

		func imagePickerControllerDidCancel(_ picker: PHPickerViewController) {
			presentationMode.dismiss()
		}

	}

	func makeCoordinator() -> Coordinator {
		return Coordinator(presentationMode: presentationMode, selectionFinishedAction: selectionFinishedAction)
	}

	func makeUIViewController(
		context: UIViewControllerRepresentableContext<ImagePicker>
	) -> PHPickerViewController {
		var config = PHPickerConfiguration(photoLibrary: .shared())
		config.filter = .images
		config.preferredAssetRepresentationMode = .compatible
		config.selectionLimit = 1
		if #available(iOS 17.0, *) {
			config.mode = .default
		}

		let picker = PHPickerViewController(configuration: config)
		picker.delegate = context.coordinator
		return picker
	}

	func updateUIViewController(
		_ uiViewController: PHPickerViewController,
		context: UIViewControllerRepresentableContext<ImagePicker>
	) {

	}
}
