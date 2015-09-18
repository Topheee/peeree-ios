//
//  SimpleBrowseViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import MultipeerConnectivity

class SimpleBrowseViewController: UIViewController, MCAdvertiserAssistantDelegate, MCBrowserViewControllerDelegate, MCSessionDelegate, UITextFieldDelegate {
	
	//use this, when we are browsing and advertising at the same time
	//	class Blubb: MCNearbyServiceBrowserDelegate {
	//		let browser: MCNearbyServiceBrowser
	//		let session: MCSession
	//
	//		func init() {
	//			browser = MCNearbyServiceBrowser(peer: <#MCPeerID!#>, serviceType: <#String!#>)
	//		}
	//
	//		@objc func browser(browser: MCNearbyServiceBrowser!, foundPeer peerID: MCPeerID!, withDiscoveryInfo info: [NSObject : AnyObject]!) {
	//			if myPeer.hash > peerID.hash {
	//				self.browser.invitePeer(peerID, toSession: session, withContext: nil, timeout: 0)
	//			}
	//		}
	//	}
	
	static private let maxPeerNameCharacters = 63
	static private let kBrowserSegueID = "kobusch-segue-browser"
	
	@IBOutlet var localPeerName: UITextField!
	@IBOutlet var adIndicator: UIActivityIndicatorView!
	
	let greeting = ["kobusch" : "hallo"]
	var adAssistant: MCAdvertiserAssistant!
	
	//browser attributes
	var browserSession: MCSession!
	var browserController: MCBrowserViewController!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	func advertiserAssistantDidDismissInvitation(advertiserAssistant: MCAdvertiserAssistant) {
		NSLog("advertiserAssistantDidDismissInvitation", advertiserAssistant)
	}
	
	func advertiserAssistantWillPresentInvitation(advertiserAssistant: MCAdvertiserAssistant) {
		
	}
	
	func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		
		if (range.length + range.location > textField.text!.characters.count )
		{
			return false;
		}
		
		let newLength = textField.text!.characters.count + string.characters.count - range.length
		return newLength <= SimpleBrowseViewController.maxPeerNameCharacters
	}
	
	@IBAction func peerNameChanged(sender: UITextField) {
		if sender.text!.characters.count <= SimpleBrowseViewController.maxPeerNameCharacters {
			LocalPeerManager.setLocalPeerName(sender.text!)
		}
	}
	
	@IBAction func startStopAdvertising(sender: UISwitch) {
		//TODO store peer ID in preferences so other devices can re-identify us
//		let defs = NSUserDefaults.standardUserDefaults()
//		defs.setObject(NSKeyedArchiver.archivedDataWithRootObject(localPeer), forKey: kPeerIDKey)
		if let advertiser = adAssistant {
			if sender.on {
				advertiser.stop()
			}
			if let adI = adIndicator {
				adI.hidden = true
			}
		} else if !sender.on {
			var localPeer = LocalPeerManager.getLocalPeer()
			if localPeerName != nil && localPeerName.text != "" {
				LocalPeerManager.setLocalPeerName(localPeerName.text!)
				localPeer = LocalPeerManager.getLocalPeer()
			}
			if let peerID = localPeer {
				//TODO fill securityIdentity
				if let peer = localPeer {
					let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: MCEncryptionPreference.Required)
					adAssistant = MCAdvertiserAssistant(serviceType: LocalPeerManager.kDiscoveryServiceID, discoveryInfo: greeting, session: session)
					
					if let advertiser = adAssistant {
						adAssistant.start()
						if let adI = adIndicator {
							adI.hidden = false
						}
					}
				}
			} else if localPeerName != nil {
				localPeerName.becomeFirstResponder()
			}
		}
	}
	
	func browserViewController(browserViewController: MCBrowserViewController, shouldPresentNearbyPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) -> Bool {
		NSLog("FirstViewController.browserViewController: shouldPresentNearbyPeer:%@ withDiscoveryInfo:%@ ", peerID.displayName, info!)
		return true
	}
	
	func browserViewControllerDidFinish(browserViewController: MCBrowserViewController) {
		NSLog("%s\n", __FUNCTION__)
		dismissViewControllerAnimated(true, completion: nil)
	}
	
	func browserViewControllerWasCancelled(browserViewController: MCBrowserViewController) {
		NSLog("%s\n", __FUNCTION__)
		dismissViewControllerAnimated(true, completion: nil)
	}
	
	func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
		NSLog("%s\n", __FUNCTION__)
	}
	
	func session(session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, withProgress progress: NSProgress) {
		//non of our business
	}
	
	func session(session: MCSession, didReceiveStream stream: NSInputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
		//non of our business
	}
	
	func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
		//non of our business
		//dispatch_async(dispatch_get_main_queue(), <#block: dispatch_block_t##() -> Void#>)
		dispatch_async(dispatch_get_main_queue()) {
			NSLog("%@\n", data)
		}
	}
	
	func session(session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, atURL localURL: NSURL, withError error: NSError?) {
		//non of our business
	}
	
	@IBAction func startBrowsing(sender: UIButton) {
		if browserSession == nil {
			var localPeer = LocalPeerManager.getLocalPeer()
			if localPeerName != nil && localPeerName.text != "" {
				LocalPeerManager.setLocalPeerName(localPeerName.text!)
				localPeer = LocalPeerManager.getLocalPeer()
			}
			if let peerID = localPeer {
				//TODO fill securityIdentity
				// setup browser session
				browserSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: MCEncryptionPreference.Required)
			
				browserSession.delegate = self
				
				browserController = MCBrowserViewController(serviceType: LocalPeerManager.kDiscoveryServiceID, session: browserSession)
				
				browserController.delegate = self;
				
				presentViewController(browserController, animated: true, completion: nil)
//				
//				if browserController.shouldPerformSegueWithIdentifier(FirstViewController.kBrowserSegueID, sender: self) {
//					browserController.prepareForSegue(UIStoryboardSegue(identifier: FirstViewController.kBrowserSegueID, source: self, destination: browserController), sender: self)
//					
//					browserController.performSegueWithIdentifier(FirstViewController.kBrowserSegueID, sender: self)
//				}
			}
		}
	}
	

}

