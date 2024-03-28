//
//  PhotoPickerWrapper.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

// https://stackoverflow.com/questions/57110290/how-to-pick-image-from-gallery-in-swiftui
struct ImagePicker: UIViewControllerRepresentable {

	@Environment(\.presentationMode)
	var presentationMode

	let selectionFinishedAction: (UIImage) -> Void

	class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {

		@Binding var presentationMode: PresentationMode

		let selectionFinishedAction: (UIImage) -> Void

		init(presentationMode: Binding<PresentationMode>, selectionFinishedAction: @escaping (UIImage) -> Void) {
			_presentationMode = presentationMode
			self.selectionFinishedAction = selectionFinishedAction
		}

		func imagePickerController(_ picker: UIImagePickerController,
								   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
			defer {
				presentationMode.dismiss()
			}

			guard let uiImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else { return }

			selectionFinishedAction(uiImage)
		}

		func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
			presentationMode.dismiss()
		}

	}

	func makeCoordinator() -> Coordinator {
		return Coordinator(presentationMode: presentationMode, selectionFinishedAction: selectionFinishedAction)
	}

	func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
		let picker = UIImagePickerController()
		picker.delegate = context.coordinator
		return picker
	}

	func updateUIViewController(_ uiViewController: UIImagePickerController,
								context: UIViewControllerRepresentableContext<ImagePicker>) {

	}
}
