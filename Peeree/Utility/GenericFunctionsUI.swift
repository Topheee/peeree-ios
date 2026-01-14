//
//  GenericFunctionsUI.swift
//  Peeree
//
//  Created by Christopher Kobusch on 04.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import UIKit
import SwiftUI

/// Tries to create an `URL` from `urlString` and open it.
@MainActor
func open(urlString: String) {
	guard let url = URL(string: urlString) else { return }

	if #available(iOS 10.0, *) {
		UIApplication.shared.open(url)
	} else {
		UIApplication.shared.openURL(url)
	}
}

// http://stackoverflow.com/questions/56533564/ddg#58341956
struct ActivityViewController: UIViewControllerRepresentable {

	let configuration: UIActivityItemsConfiguration

	func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
		return UIActivityViewController(activityItemsConfiguration: self.configuration)
	}

	func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
}

extension UIImage {
	/// Extract a squared image from the center.
	public func centerSquared() -> CGImage? {
		guard self.size.width != self.size.height else { return self.cgImage }

		let edgeLength = min(self.size.width, self.size.height)
		let size = CGSize(squareEdgeLength: edgeLength)

		let x: CGFloat, y: CGFloat

		switch self.imageOrientation {
		case .up, .down, .upMirrored, .downMirrored:
			x = (self.size.width - edgeLength) / 2
			y = (self.size.height - edgeLength) / 2
		case .left, .right, .leftMirrored, .rightMirrored:
			x = (self.size.height - edgeLength) / 2
			y = (self.size.width - edgeLength) / 2
		@unknown default:
			assertionFailure()
			x = (self.size.width - edgeLength) / 2
			y = (self.size.height - edgeLength) / 2
		}

		let cropRect = CGRect(origin: CGPoint(x: x, y: y), size: size)

		return self.cgImage?.cropping(to: cropRect)
	}

	// https://stackoverflow.com/a/40867644
	func scaled(to newSize: CGSize) -> UIImage {
		let image = UIGraphicsImageRenderer(size: newSize).image { _ in
			draw(in: CGRect(origin: .zero, size: newSize))
		}

		return image.withRenderingMode(renderingMode)
	}
}
