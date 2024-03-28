//
//  DiscoveryBackgroundView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI
import SpriteKit

public struct DiscoveryBackgroundView: View {

	let lookingOut: Bool

	public var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: 16)
				.fill(Color("ColorDivider"))

			if lookingOut {
				GeometryReader { proxy in
					DiscoveryBackgroundContainerView(proxy: proxy)
				}
				.clipShape(RoundedRectangle(cornerRadius: 16))
			}
		}
	}
}

#Preview {
	DiscoveryBackgroundView(lookingOut: true)
}

#Preview {
	DiscoveryBackgroundView(lookingOut: false)
}


struct DiscoveryBackgroundContainerView: View {
	var proxy: GeometryProxy

	var body: some View {
		SpriteView(
			scene: DiscoveryBackgroundScene(size: proxy.size)
		)
		.blur(radius: 18)
	}
}

class DiscoveryBackgroundScene: SKScene {

	override func didMove(to view: SKView) {
		backgroundColor = UIColor.systemBackground
		launchDiscoveryBackground()
	}

	func launchDiscoveryBackground() {
		guard let node = SKEmitterNode(fileNamed: "DiscoveryParticle") else { return }

		node.position = CGPoint(x: size.width / 2, y: size.height / 2)
		addChild(node)
	}
}
