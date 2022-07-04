//
//  NetworkReachability.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.08.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//
//  Based on the Apple Reachability sample code.
//

import Foundation

import SystemConfiguration

class Reachability {
	static let ReachabilityChangedNotification = "kNetworkReachabilityChangedNotification"
	
	let reachabilityRef: SCNetworkReachability
	
	enum NetworkStatus: Int {
		case notReachable, reachableViaWiFi, reachableViaWWAN
	}
	
	//	static let ShouldPrintReachabilityFlags = true
	//
	//	static func PrintReachabilityFlags(flags: SCNetworkReachabilityFlags, comment: String) {
	//		if ShouldPrintReachabilityFlags {
	//			NSLog("Reachability Flag Status: %c%c %c%c%c%c%c%c%c %s\n",
	//				   (flags & SCNetworkReachabilityFlags.IsWWAN.rawValue)		 ? "W" : "-",
	//				   (flags & SCNetworkReachabilityFlags.Reachable)			? "R" : "-",
	//
	//				   (flags & SCNetworkReachabilityFlags.TransientConnection)  ? "t" : "-",
	//				   (flags & SCNetworkReachabilityFlags.ConnectionRequired)   ? "c" : "-",
	//				   (flags & SCNetworkReachabilityFlags.ConnectionOnTraffic)  ? "C" : "-",
	//				   (flags & SCNetworkReachabilityFlags.InterventionRequired) ? "i" : "-",
	//				   (flags & SCNetworkReachabilityFlags.ConnectionOnDemand)   ? "D" : "-",
	//				   (flags & SCNetworkReachabilityFlags.IsLocalAddress)	   ? "l" : "-",
	//				   (flags & SCNetworkReachabilityFlags.IsDirect)			 ? "d" : "-",
	//				   comment
	//			);
	//		}
	//	}
	
	static func getNetworkStatus() -> NetworkStatus {
		guard let instance = Reachability() else { return .notReachable }
		
		return instance.currentReachabilityStatus()
	}
	
	init?(hostName: String) {
		guard let tmp = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, hostName) else { return nil } //hostName.UTF8String
		reachabilityRef = tmp
	}
	
	init?(hostAddress: sockaddr) {
		var mutableAddress = hostAddress
		guard let tmp = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, &mutableAddress) else { return nil }
		reachabilityRef = tmp
	}
	
	init?() {
		var zeroAddress = sockaddr_in()
		bzero(&zeroAddress, MemoryLayout<sockaddr_in>.size)
		zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
		zeroAddress.sin_family = UInt8(AF_INET)
		var mutableAddress = zeroAddress
		guard let tmp = (withUnsafePointer(to: &mutableAddress) { (unsafePointer) -> SCNetworkReachability? in
			return unsafePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { (unsafeMutablePointer) in
				SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, unsafeMutablePointer)
			}
		}) else { return nil }
		
		reachabilityRef = tmp
	}
	
/* dead, probably non-working code
	func startNotifier() -> Bool {
		var returnValue = false
		var selfptr = bridge(obj: self)
		var context = SCNetworkReachabilityContext(version: 0, info: &selfptr, retain: nil, release: nil, copyDescription: nil)
		
		if (SCNetworkReachabilitySetCallback(reachabilityRef, ({(target: SCNetworkReachability, flags: SCNetworkReachabilityFlags, info: UnsafeMutableRawPointer?) in
			assert(info != nil, "info was NULL in ReachabilityCallback")
			let noteObject: Reachability = bridge(ptr: info!)
			
			// Post a notification to notify the client that the network reachability changed.
			DispatchQueue.main.async {
				NotificationCenter.`default`.post(name: Notification.Name(rawValue: Reachability.ReachabilityChangedNotification), object: noteObject)
			}
		}), &context)) {
			if (SCNetworkReachabilityScheduleWithRunLoop(reachabilityRef, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)) {
				returnValue = true
			}
		}
		
		return returnValue
	}
	
	
	func stopNotifier() {
		SCNetworkReachabilityUnscheduleFromRunLoop(reachabilityRef, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
	}
	
	deinit {
		stopNotifier()
	}
*/
	
	func networkStatusForFlags(_ flags: SCNetworkReachabilityFlags) -> NetworkStatus {
		//		Reachability.PrintReachabilityFlags(flags, "networkStatusForFlags")
		if !flags.contains(SCNetworkReachabilityFlags.reachable) {
			// The target host is not reachable.
			return .notReachable
		}
		
		var returnValue = NetworkStatus.notReachable
		
		if !flags.contains(SCNetworkReachabilityFlags.connectionRequired) {
			// If the target host is reachable and no connection is required then we'll assume (for now) that you're on Wi-Fi...
			returnValue = .reachableViaWiFi
		}
		
		if flags.contains(SCNetworkReachabilityFlags.connectionOnDemand) || flags.contains(SCNetworkReachabilityFlags.connectionOnTraffic) {
			// ... and the connection is on-demand (or on-traffic) if the calling application is using the CFSocketStream or higher APIs...
			if !flags.contains(SCNetworkReachabilityFlags.interventionRequired) {
				// ... and no [user] intervention is needed...
				returnValue = .reachableViaWiFi
			}
		}
		
		#if os(iOS)
		if flags.contains(SCNetworkReachabilityFlags.isWWAN) {
			// ... but WWAN connections are OK if the calling application is using the CFNetwork APIs.
			returnValue = .reachableViaWWAN
		}
		#endif
		
		return returnValue
	}
	
	func connectionRequired() -> Bool {
		var flags: SCNetworkReachabilityFlags = []
		
		if (SCNetworkReachabilityGetFlags(reachabilityRef, &flags)) {
			return flags.contains(SCNetworkReachabilityFlags.connectionRequired)
		}
		
		return false
	}
	
	func currentReachabilityStatus() -> NetworkStatus {
		var returnValue = NetworkStatus.notReachable
		var flags: SCNetworkReachabilityFlags = []
		
		if (SCNetworkReachabilityGetFlags(reachabilityRef, &flags)) {
			returnValue = networkStatusForFlags(flags)
		}
		
		return returnValue
	}
}
