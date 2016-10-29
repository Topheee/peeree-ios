//
//  MCSessionMock.swift
//  Peeree
//
//  Created by Christopher Kobusch on 05.02.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import MultipeerConnectivity

class MCSessionMock: MCSession {
    override init(peer myPeerID: MCPeerID, securityIdentity identity: [Any]?, encryptionPreference: MCEncryptionPreference) {
        super.init(peer: myPeerID, securityIdentity: identity, encryptionPreference: encryptionPreference)
    }
	
    override func disconnect() {
        DispatchQueue.global().async {
            self.delegate?.session(self, peer: self.myPeerID, didChange: .notConnected)
        }
    }
}
