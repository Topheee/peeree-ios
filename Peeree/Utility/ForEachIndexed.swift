//
//  ForEachIndexed.swift
//  Peeree
//
//  Created by Christopher Kobusch on 21.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

// https://stackoverflow.com/a/68965407
struct ForEachIndexed
<Data: MutableCollection&RandomAccessCollection, RowContent: View, ID: Hashable>:
	View, @preconcurrency DynamicViewContent where Data.Index : Hashable
{
	var data: [(Data.Index, Data.Element)] {
		forEach.data
	}

	let forEach: ForEach<[(Data.Index, Data.Element)], ID, RowContent>

	init(_ data: Binding<Data>,
		 @ViewBuilder rowContent: @escaping (Data.Index, Binding<Data.Element>) -> RowContent
	) where Data.Element: Identifiable, Data.Element.ID == ID {
		forEach = ForEach(
			Array(zip(data.wrappedValue.indices, data.wrappedValue)),
			id: \.1.id
		) { i, _ in
			rowContent(i, Binding(get: { data.wrappedValue[i] }, set: { data.wrappedValue[i] = $0 }))
		}
	}

	init(_ data: Binding<Data>,
		 id: KeyPath<Data.Element, ID>,
		 @ViewBuilder rowContent: @escaping (Data.Index, Binding<Data.Element>) -> RowContent
	) {
		forEach = ForEach(
			Array(zip(data.wrappedValue.indices, data.wrappedValue)),
			id: (\.1 as KeyPath<(Data.Index, Data.Element), Data.Element>).appending(path: id)
		) { i, _ in
			rowContent(i, Binding(get: { data.wrappedValue[i] }, set: { data.wrappedValue[i] = $0 }))
		}
	}

	init(
		_ data: Data,
		@ViewBuilder rowContent: @escaping (Data.Index, Data.Element) -> RowContent
	) where Data.Element: Identifiable, Data.Element.ID == ID {
		forEach = ForEach(
			Array(zip(data.indices, data)),
			id: \.1.id
		) { i, _ in
			rowContent(i, data[i])
		}
	}

	var body: some View {
		forEach
	}
}

