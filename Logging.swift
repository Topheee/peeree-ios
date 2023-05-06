//
//  Logging.swift
//  Peeree
//
//  Created by Christopher Kobusch on 17.04.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import OSLog

/// Debug-level logging of `message`.
public func dlog(_ message: @autoclosure () -> String) {
#if DEBUG
	os_log("%@", log: .default, type: .debug, "[DBG] \(message())")
#endif
}

/// Info-level logging of `message`.
public func ilog(_ message: String) {
	os_log("%@", log: .default, type: .info, "[INF] \(message)")
}

/// Warning-level logging of `message`.
public func wlog(_ message: String) {
	os_log("%@", log: .default, type: .default, "[WRN] \(message)")
}

/// Error-level logging of `message`.
public func elog(_ message: String) {
	os_log("%@", log: .default, type: .error, "[ERR] \(message)\n\(Thread.callStackSymbols)")
}

/// Fault-level logging of `message`.
public func flog(_ message: String) {
	os_log("%@", log: .default, type: .fault, "[FAL] \(message)\n\(Thread.callStackSymbols)")
}
