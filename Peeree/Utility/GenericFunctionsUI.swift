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
