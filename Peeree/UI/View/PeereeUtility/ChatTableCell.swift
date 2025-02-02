//
//  ChatTableCell.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI
import PeereeCore
import PeereeServerChat
import PeereeDiscovery

struct ChatTableCell: View {

	@ObservedObject var chatPersona: ServerChatPerson

	@ObservedObject var discoveryPersona: DiscoveryPerson

	var body: some View {
		HStack {
			discoveryPersona.image
				.resizable()
				.frame(width: 72, height: 72)
				.aspectRatio(contentMode: .fit)
				.clipShape(Circle())

			VStack(alignment: .leading) {
				Text(discoveryPersona.info.nickname).font(.title).lineLimit(1)
				Text(((chatPersona.lastMessage?.sent ?? false) ? "📤 " : (chatPersona.unreadMessages > 0 ? "📬 " : "📭 ")) + (chatPersona.lastMessage?.message ?? NSLocalizedString("No messages.", comment: "Placeholder text")))
					.font(.subheadline)
					.modify {
						if #available(iOS 16, *) {
							$0.italic(chatPersona.lastMessage == nil)
						} else {
							if chatPersona.lastMessage == nil {
								$0.italic()
							}
						}
					}
					.lineLimit(1)
			}

			Spacer()

			if chatPersona.unreadMessages > 0 {
				Text("\(chatPersona.unreadMessages)")
					.font(.subheadline)
					.fontWeight(.light)
					.foregroundColor(.white)
					.padding(12)
					.background(Circle().fill(Color.blue))
			}
		}
		.padding()
	}
}

#Preview {
	let cs = ServerChatViewState()
	let ds = DiscoveryViewState()
	let peerID = PeerID()

	let scp = cs.addPersona(of: peerID, with: ())
	scp.set(lastReadDate: Date.distantPast)
	scp.unreadMessages = 1
	scp.insert(messages: [demoMessage(sent: false, message: "Hello there!", timestamp: Date())], sorted: true)

	let dp = ds.demo(peerID)

	return ChatTableCell(chatPersona: scp, discoveryPersona: dp)
}
