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
public func dlog(_ tag: String, _ message: @autoclosure () -> String) {
#if DEBUG
	os_log("[DBG] [%@] %@", log: .default, type: .debug, tag, message())
#endif
}

/// Info-level logging of `message`.
public func ilog(_ tag: String, _ message: String) {
	os_log("[INF] [%@] %@", log: .default, type: .info, tag, message)
}

/// Warning-level logging of `message`.
public func wlog(_ tag: String, _ message: String) {
	os_log("[WRN] [%@] %@", log: .default, type: .default, tag, message)
}

/// Error-level logging of `message`.
public func elog(_ tag: String, _ message: String) {
	os_log("[ERR] [%@] %@\n%@", log: .default, type: .error, tag, message, Thread.callStackSymbols)
}

/// Fault-level logging of `message`.
public func flog(_ tag: String, _ message: String) {
	os_log("[FAL] [%@] %@\n%@", log: .default, type: .fault, tag, message, Thread.callStackSymbols)
}
