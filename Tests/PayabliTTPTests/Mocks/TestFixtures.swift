import Foundation
@testable import PayabliTTP

enum TestFixtures {

    static func makeConfigResponse() -> ConfigResponse {
        let json = """
        {
            "fiserv": {
                "secretKey": "test-secret",
                "apiKey": "test-fiserv-key",
                "environment": "CERT",
                "currencyCode": "USD",
                "merchantId": "M123",
                "appleTtpMerchantId": "ATTP123",
                "merchantName": "Test Merchant",
                "merchantCategoryCode": "1000",
                "terminalId": "T001",
                "terminalProfileId": "TP001"
            },
            "requestToken": "mock-request-token"
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(ConfigResponse.self, from: json)
    }

    static func makeChallengeResponse() -> ChallengeResponse {
        let json = """
        { "challenge": "\(Data("test-challenge".utf8).base64EncodedString())" }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(ChallengeResponse.self, from: json)
    }

    static func makeTransactionResponse(paymentTransId: String = "txn-001") -> TransactionResponse {
        let json = """
        { "data": { "paymentTransId": "\(paymentTransId)" } }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(TransactionResponse.self, from: json)
    }
}
