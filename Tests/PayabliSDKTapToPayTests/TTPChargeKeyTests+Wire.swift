import Foundation
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils

// MARK: - The stub service

@available(iOS 16.7, *)
extension TTPChargeKeyTests {
    final class Wire: @unchecked Sendable {
        private let lock = NSLock()
        private var sentKeys: [String] = []
        private var initiate = 200
        private var refusal: String?
        private var duplicateSale = false
        private var closeFails = false
        private var notApproved = false
        private var refusesCustomer = false

        var keys: [String] {
            lock.withLock { sentKeys }
        }

        var initiateStatus: Int {
            get { lock.withLock { initiate } }
            set { lock.withLock { initiate = newValue } }
        }

        var updateRefusal: String? {
            get { lock.withLock { refusal } }
            set { lock.withLock { refusal = newValue } }
        }

        var conflictIsDuplicateSale: Bool {
            get { lock.withLock { duplicateSale } }
            set { lock.withLock { duplicateSale = newValue } }
        }

        var initiateNotApproved: Bool {
            get { lock.withLock { notApproved } }
            set { lock.withLock { notApproved = newValue } }
        }

        var updateFails: Bool {
            get { lock.withLock { closeFails } }
            set { lock.withLock { closeFails = newValue } }
        }

        var initiateRefusesCustomer: Bool {
            get { lock.withLock { refusesCustomer } }
            set { lock.withLock { refusesCustomer = newValue } }
        }

        func record(_ key: String?) {
            lock.withLock { sentKeys.append(key ?? "<none>") }
        }

        func reset() {
            lock.withLock {
                sentKeys = []
                initiate = 200
                refusal = nil
                duplicateSale = false
                closeFails = false
                notApproved = false
                refusesCustomer = false
            }
        }
    }

    static let stubHandler: StubURLProtocol.Handler = { request in
        let path = request.url?.path ?? ""
        var status = 200
        var contentType = "application/json"
        let data: Data
        if path.contains("/MoneyIn/initiate") {
            wire.record(request.value(forHTTPHeaderField: "idempotencyKey"))
            status = wire.initiateStatus
            if wire.initiateRefusesCustomer {
                status = 400
                let message = "Missing customer identifiers: customerNumber"
                data = try JSONSerialization.data(withJSONObject: [
                    "title": "Bad Request",
                    "status": 400,
                    "detail": message,
                    "code": "E7020",
                    "errors": ["customerData": [["message": message, "suggestion": ""]]]
                ])
            } else if status == 409, wire.conflictIsDuplicateSale {
                data = try JSONSerialization.data(withJSONObject: ["isSuccess": false, "responseText": "Duplicated transaction"])
            } else if wire.initiateNotApproved {
                data = try JSONSerialization.data(withJSONObject: ["code": "D01", "reason": "Refused"])
            } else if status == 409 {
                contentType = "text/plain"
                data = Data("Duplicated idempotencyKey".utf8)
            } else {
                data = try JSONSerialization.data(withJSONObject: ["code": "A01", "data": ["paymentTransId": "TXN-KEY"]])
            }
        } else if path.contains("/MoneyIn/update/") {
            if wire.updateFails {
                status = 500
                data = try JSONSerialization.data(withJSONObject: ["title": "Server Error", "status": 500])
            } else if let refusal = wire.updateRefusal {
                status = 400
                data = try JSONSerialization.data(withJSONObject: ["title": "Bad Request", "status": 400, "detail": refusal])
            } else {
                data = try JSONSerialization.data(withJSONObject: ["code": "A01", "data": ["paymentTransId": "TXN-KEY"]])
            }
        } else {
            data = try JSONSerialization.data(withJSONObject: [
                "responseCode": 1,
                "isSuccess": true,
                "responseData": [
                    "credentials": ["secretKey": "s", "apiKey": "a", "merchantId": "m", "terminalId": "t"]
                ],
                "paymentToken": "payment_tok"
            ])
        }
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType]
            )!,
            data
        )
    }
}
