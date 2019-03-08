//
//  InAppReceipt.swift
//  SwiftyStoreKit
//
//  Created by phimage on 22/12/15.
// Copyright (c) 2015 Andrea Bizzotto (bizz84@gmail.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import Firebase

// https://developer.apple.com/library/ios/releasenotes/General/ValidateAppStoreReceipt/Chapters/ValidateRemotely.html

public struct FirebaseFunctionReceiptValidator: ReceiptValidator {

	lazy var functions = Functions.functions()

	public enum VerifyReceiptURLType: String {
		case production = "https://buy.itunes.apple.com/verifyReceipt"
		case sandbox = "https://sandbox.itunes.apple.com/verifyReceipt"
	}

    private let service: VerifyReceiptURLType
    private let sharedSecret: String?

    /**
     * Reference Apple Receipt Validator
     *  - Parameter service: Either .production or .sandbox
     *  - Parameter sharedSecret: Only used for receipts that contain auto-renewable subscriptions. Your app’s shared secret (a hexadecimal string).
     */
    public init(service: VerifyReceiptURLType = .production, sharedSecret: String? = nil) {
		self.service = service
        self.sharedSecret = sharedSecret
	}

	public func validate(receiptData: Data, completion: @escaping (VerifyReceiptResult) -> Void) {
	
		let receipt = receiptData.base64EncodedString(options: [])
		let requestContents: NSMutableDictionary = [ "receipt-data": receipt ]
		// password if defined
		if let password = sharedSecret {
			requestContents.setValue(password, forKey: "password")
		}
		
		functions.httpsCallable("validate").call(receipt) { (result, error) in
 			if let error = error as NSError? {
    			if error.domain == FunctionsErrorDomain {
      			let code = FunctionsErrorCode(rawValue: error.code)
      			let message = error.localizedDescription
      			let details = error.userInfo[FunctionsErrorDetailsKey]
				completetion(error)
				return
    		} else if let safeData = result?.data {
				guard let receiptInfo = try? JSONSerialization.jsonObject(with: safeData, options: .mutableLeaves) as? ReceiptInfo ?? [:] else {
					let jsonStr = String(data: safeData, encoding: String.Encoding.utf8)
					completion(.error(error: .jsonDecodeError(string: jsonStr)))
					return
				}
				if let status = receiptInfo["status"] as? Int {
					let receiptStatus = ReceiptStatus(rawValue: status) ?? ReceiptStatus.unknown
					if case .testReceipt = receiptStatus {
                    	let sandboxValidator = AppleReceiptValidator(service: .sandbox, sharedSecret: self.sharedSecret)
						sandboxValidator.validate(receiptData: receiptData, completion: completion)
					} else {
						if receiptStatus.isValid {
							completion(.success(receipt: receiptInfo))
						} else {
							completion(.error(error: .receiptInvalid(receipt: receiptInfo, status: receiptStatus)))
						}
					}
				} else {
					completion(.error(error: .receiptInvalid(receipt: receiptInfo, status: ReceiptStatus.none)))
				}
			}
			completion(.error(error: .noRemoteData))
			return 
  		}
	}
}
