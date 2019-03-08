// Receipt Validator for personal project

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
				//Fix this completetion
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
