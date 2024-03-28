//
//  FlipGroupView3.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

// http://stackoverflow.com/questions/62652421/ddg#62652866
@ViewBuilder
func FlipGroupView3<V1: View, V2: View, V3: View>(if value: Bool,
				@ViewBuilder _ content: @escaping () -> TupleView<(V1, V2, V3)>) -> some View {
	let pair = content()
	if value {
		TupleView((pair.value.2, pair.value.1, pair.value.0))
	} else {
		TupleView((pair.value.0, pair.value.1, pair.value.2))
	}
}
