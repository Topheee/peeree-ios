//
// AuthenticationAPI.swift
//
// Generated by swagger-codegen
// https://github.com/swagger-api/swagger-codegen
//

import Foundation



open class AuthenticationAPI {
    /**
     Request Public Key Reset

     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func deleteAccountSecurityPublicKey(completion: @escaping ((_ data: Void?,_ error: ErrorResponse?) -> Void)) {
        deleteAccountSecurityPublicKeyWithRequestBuilder().execute { (response, error) -> Void in
            if error == nil {
                completion((), error)
            } else {
                completion(nil, error)
            }
        }
    }


    /**
     Request Public Key Reset
     - DELETE /account/security/public_key
     - Sends a random number to the user's e-mail address, which has then to be passed along when resetting the public key in the PUT variant of this request. The key is only valid for 30 minutes.  Note that the signature is optional here, as the user may has lost his phone. If it is passed, it still has to be computed with the current sequence number and private key!
     - API Key:
       - type: apiKey peerID
       - name: peerID
     - API Key:
       - type: apiKey signature
       - name: signature

     - returns: RequestBuilder<Void>
     */
    open class func deleteAccountSecurityPublicKeyWithRequestBuilder() -> RequestBuilder<Void> {
        let path = "/account/security/public_key"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil

        let url = URLComponents(string: URLString)!

        let requestBuilder: RequestBuilder<Void>.Type = SwaggerClientAPI.requestBuilderFactory.getNonDecodableBuilder()

        return requestBuilder.init(method: .DELETE, url: url.url!, parameters: parameters, isBody: false)
    }

    /**
     Reset Sequence Number

     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func deleteAccountSecuritySequenceNumber(completion: @escaping ((_ data: Int32?,_ error: ErrorResponse?) -> Void)) {
        deleteAccountSecuritySequenceNumberWithRequestBuilder().execute { (response, error) -> Void in
            completion(response?.body, error)
        }
    }


    /**
     Reset Sequence Number
     - DELETE /account/security/sequence_number
     - Generates a new random sequence number, which is a per-request incrementing integer number to prevent from replay attacks. This number has to be incremented by 13 after each request.  For this call the signature can be omitted as it should only be needed if the sequence numbers of the client and the server do not match any more and therefore the client anyway cannot compute the correct signature.
     - API Key:
       - type: apiKey peerID
       - name: peerID
     - examples: [{contentType=application/json, example=0}]

     - returns: RequestBuilder<Int>
     */
    open class func deleteAccountSecuritySequenceNumberWithRequestBuilder() -> RequestBuilder<Int32> {
        let path = "/account/security/sequence_number"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil

        let url = URLComponents(string: URLString)!

        let requestBuilder: RequestBuilder<Int32>.Type = SwaggerClientAPI.requestBuilderFactory.getNonDecodableBuilder()

        return requestBuilder.init(method: .DELETE, url: url.url!, parameters: parameters, isBody: false)
    }

    /**
     Reset Public Key
     - parameter publicKey: (query) See PublicKey in Definitions section.       - parameter randomNumber: (query) The number sent to the user&#x27;s e-mail in the delete variant of this request.
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func putAccountSecurityPublicKey(publicKey: Data, randomNumber: String, completion: @escaping ((_ data: String?,_ error: ErrorResponse?) -> Void)) {
        putAccountSecurityPublicKeyWithRequestBuilder(publicKey: publicKey, randomNumber: randomNumber).execute { (response, error) -> Void in
            completion(response?.body, error)
        }
    }


    /**
     Reset Public Key
     - PUT /account/security/public_key
     - Establishes a new public key for the user as well as a new sequence number. This request is intended to be used when the user moved to a new device.
     - API Key:
       - type: apiKey peerID
       - name: peerID
     - examples: [{contentType=application/json, example=""}]
     - parameter publicKey: (query) See PublicKey in Definitions section.       - parameter randomNumber: (query) The number sent to the user&#x27;s e-mail in the delete variant of this request.

     - returns: RequestBuilder<String>
     */
    open class func putAccountSecurityPublicKeyWithRequestBuilder(publicKey: Data, randomNumber: String) -> RequestBuilder<String> {
        let path = "/account/security/public_key"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil
        var url = URLComponents(string: URLString)!
        url.queryItems = APIHelper.mapValuesToQueryItems([
                        "publicKey": publicKey,
                        "randomNumber": randomNumber
        ])

        let requestBuilder: RequestBuilder<String>.Type = SwaggerClientAPI.requestBuilderFactory.getNonDecodableBuilder()

        return requestBuilder.init(method: .PUT, url: url.url!, parameters: parameters, isBody: false)
    }

}
