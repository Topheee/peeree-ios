//
// Account.swift
//
// Generated by swagger-codegen
// https://github.com/swagger-api/swagger-codegen
//

import Foundation


public struct Account: Codable {


    public var peerID: PeerID

    /** Random sequence number encrypted with the public key of the user.  */
    public var sequenceNumber: Int32
    public init(peerID: PeerID, sequenceNumber: Int32) {
        self.peerID = peerID
        self.sequenceNumber = sequenceNumber
    }

}
