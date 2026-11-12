@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// Answers each call with the next step of its script, and records the key each call sent.
///
/// Every step but a failure before the hand-off marks the send as one that may have left the device.
final class ScriptedTransport: PayabliTransport, @unchecked Sendable {
    enum Step {
        case approved
        case declined
        case duplicate
        case duplicatePayment
        case conflict(String)
        case lost
        case unauthorized
        /// A 401 carrying a fraud block's code, which lowers the mark as every 401 does.
        case fraudBlocked401(String)
        case lostBeforeHandOff
        case tokenFetchFailed
        case cancelled(afterHandOff: Bool)
        case urlErrorCancelled
        /// Refused on the device before the request left, as a field the SDK would not send.
        case refusedBeforeHandOff(PayabliPayInError.InvalidInput)
    }

    private static let approved = Data("""
    {"code":"A0000","reason":"Approved","responseData":{"authCode":"1","referenceId":"trans-1"}}
    """.utf8)
    private static let declined = Data("""
    {"code":"D0001","reason":"Declined","explanation":"Declined by the issuer."}
    """.utf8)

    private static let duplicatePayment = Data("""
    {"responseText":"Duplicate payment","isSuccess":false,
     "responseData":{"resultCode":3,"referenceId":"trans-0","resultText":"Approved"}}
    """.utf8)

    private let lock = NSLock()
    private var keys: [String] = []
    private var steps: [Step] = []
    private var inFlight: (() -> Void)?

    /// Runs while each call is in flight, after its key is recorded.
    var duringSend: (() -> Void)? {
        get { lock.withLock { inFlight } }
        set { lock.withLock { inFlight = newValue } }
    }

    var script: [Step] {
        get { lock.withLock { steps } }
        set { lock.withLock { steps = newValue } }
    }

    var sentKeys: [String] {
        lock.withLock { keys }
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        let step: Step = lock.withLock {
            keys.append(request.headers["idempotencyKey"] ?? "")
            return steps.isEmpty ? .lost : steps.removeFirst()
        }
        switch step {
        case .lostBeforeHandOff, .cancelled(afterHandOff: false), .tokenFetchFailed, .refusedBeforeHandOff:
            break
        default:
            PayabliSendMark.current?.set()
        }
        duringSend?()
        switch step {
        case .approved:
            return PayabliResponse(statusCode: 200, headers: [:], body: Self.approved)
        case .declined:
            return PayabliResponse(statusCode: 200, headers: [:], body: Self.declined)
        case .duplicate:
            let refusal = "Duplicated idempotencyKey: \(request.headers["idempotencyKey"] ?? "")"
            return PayabliResponse(statusCode: 409, headers: [:], body: Data(refusal.utf8))
        case .duplicatePayment:
            return PayabliResponse(statusCode: 409, headers: [:], body: Self.duplicatePayment)
        case let .conflict(body):
            return PayabliResponse(statusCode: 409, headers: [:], body: Data(body.utf8))
        case .tokenFetchFailed:
            throw PayabliGenericError(type: .tokenProviderFailed, reason: "No token")
        case .lost, .lostBeforeHandOff:
            throw PayabliGenericError(type: .networkError, reason: "The response was lost.")
        case .cancelled:
            throw CancellationError()
        case .urlErrorCancelled:
            throw URLError(.cancelled)
        case .unauthorized:
            throw PayabliGenericError(type: .tokenExpired, reason: "Token expired")
        case let .refusedBeforeHandOff(refusal):
            throw refusal
        case let .fraudBlocked401(code):
            PayabliSendMark.current?.lower()
            let body = #"{"code":"\#(code)","reason":"Blocked","explanation":"The payer is blocked.","data":null}"#
            return PayabliResponse(statusCode: 401, headers: [:], body: Data(body.utf8))
        }
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        let response = try await perform(request)
        try mapPayabliHTTPError(response: response)
        return try decodePayabliV2Envelope(T.self, from: response)
    }
}
