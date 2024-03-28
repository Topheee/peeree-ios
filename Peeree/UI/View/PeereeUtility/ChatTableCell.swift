//
//  ChatTableCell.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

struct ChatTableCell: View {
	let portrait: Image

	let personName: String

	let lastMessage: String

	let unreadMessageCount: Int

	var body: some View {
		HStack {
			portrait
				.resizable()
				.frame(width: 72, height: 72)
				.aspectRatio(contentMode: .fit)
				.clipShape(Circle())

			VStack(alignment: .leading) {
				Text(personName).font(.title).lineLimit(1)
				Text(lastMessage == "" ? "No messages." : lastMessage)
					.font(.subheadline)
					.modify {
						if #available(iOS 16, *) {
							$0.italic(lastMessage == "")
						} else {
							if lastMessage == "" {
								$0.italic()
							}
						}
					}
					.lineLimit(1)
			}

			Spacer()

			if unreadMessageCount > 0 {
				Text("\(unreadMessageCount)")
					.padding()
					.background(Circle().fill(Color.blue))
			}
		}
		.padding()
	}
}

#Preview {
	ChatTableCell(portrait: Image("p1"), personName: "Lea", lastMessage: "Hi there", unreadMessageCount: 1)
}

#Preview {
	ChatTableCell(portrait: Image("p2"), personName: "Anna", lastMessage: "General Kenobi", unreadMessageCount: 1)
}

#Preview {
	ChatTableCell(portrait: Image("p3"), personName: "Anna", lastMessage: "", unreadMessageCount: 0)
}

struct ChatTableCell2: View {

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
				Text(chatPersona.lastMessage?.message ?? "No messages.")
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
					.padding()
					.background(Circle().fill(Color.blue))
			}
		}
		.padding()
	}
}
