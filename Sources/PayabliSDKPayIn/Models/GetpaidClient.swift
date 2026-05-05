import Foundation
import PayabliSDKCore

// MARK: - Client

/// Client for `POST /api/v2/MoneyIn/getpaid`.
///
/// See PRD §8.1.1 "Payment Processing Endpoint (getpaid)" and §9.3A–C.
/// Request payload types live in `GetpaidWireFormat.swift`.
public final class GetpaidClient: Sendable {
    private let service: PayabliService
    private let auth: PayabliAuth
    private let logger = PayabliLogger(category: .tokenization)

    public init(service: PayabliService, auth: PayabliAuth) {
        self.service = service
        self.auth = auth
    }

    public func chargeCard(
        payload: CardTokenizationPayload,
        request: PayabliPaymentRequest,
        customerId: Int,
        entryPoint: String
    ) async throws -> PayabliTransactionResult {
        let initiator = request.initiator ?? .payor
        let method = GetpaidCardMethod(
            payload: payload,
            saveIfSuccess: request.saveIfSuccess,
            initiator: initiator
        )
        return try await sendGetpaid(
            method: method,
            request: request,
            customerId: customerId,
            entryPoint: entryPoint
        )
    }

    public func chargeACH(
        payload: ACHTokenizationPayload,
        request: PayabliPaymentRequest,
        customerId: Int,
        entryPoint: String
    ) async throws -> PayabliTransactionResult {
        let initiator = request.initiator ?? .payor
        let method = GetpaidACHMethod(
            payload: payload,
            saveIfSuccess: request.saveIfSuccess,
            initiator: initiator
        )
        return try await sendGetpaid(
            method: method,
            request: request,
            customerId: customerId,
            entryPoint: entryPoint
        )
    }

    public func chargeApplePay(
        token: ApplePayToken,
        request: PayabliPaymentRequest,
        customerId: Int,
        entryPoint: String
    ) async throws -> PayabliTransactionResult {
        let initiator = request.initiator ?? .payor
        let method = GetpaidApplePayMethod(
            token: token,
            saveIfSuccess: request.saveIfSuccess,
            initiator: initiator
        )
        return try await sendGetpaid(
            method: method,
            request: request,
            customerId: customerId,
            entryPoint: entryPoint
        )
    }

    public func chargeStoredMethod(
        methodType: PayabliPaymentType,
        request: PayabliPaymentRequest,
        customerId: Int,
        entryPoint: String
    ) async throws -> PayabliTransactionResult {
        guard let storedMethodId = request.storedMethodId else {
            throw PayabliGenericError(
                code: .invalidConfiguration,
                reason: "chargeStoredMethod requires storedMethodId"
            )
        }
        let initiator = request.initiator ?? .merchant
        let methodString: String
        switch methodType {
        case .card: methodString = "card"
        case .ach: methodString = "ach"
        default:
            throw PayabliGenericError(
                code: .invalidConfiguration,
                reason: "Stored-method charges support only .card or .ach"
            )
        }
        let method = GetpaidStoredMethod(
            method: methodString,
            storedMethodId: storedMethodId,
            initiator: initiator.apiValue,
            storedMethodUsageType: request.storedMethodUsageType?.apiValue
        )
        return try await sendGetpaid(
            method: method,
            request: request,
            customerId: customerId,
            entryPoint: entryPoint
        )
    }

    // MARK: - Core HTTP

    private func sendGetpaid<M: Encodable>(
        method: M,
        request: PayabliPaymentRequest,
        customerId: Int,
        entryPoint: String
    ) async throws -> PayabliTransactionResult {
        let idempotencyKey = request.idempotencyKey ?? UUID().uuidString

        let body = GetpaidRequest(
            entryPoint: entryPoint,
            ipaddress: nil,
            customerData: CustomerDataBlock(customerId: customerId),
            paymentDetails: GetpaidPaymentDetails(
                totalAmount: request.totalAmount,
                serviceFee: request.serviceFee,
                currency: request.currency,
                categories: request.categories,
                invoiceData: request.invoiceData
            ),
            paymentMethod: method,
            source: "mobile"
        )

        return try await withAuthRetry { token in
            let httpRequest = try PayabliRequest.json(
                method: .post,
                path: "/api/v2/MoneyIn/getpaid",
                headers: [
                    "Authorization": "Bearer \(token)",
                    "idempotencyKey": idempotencyKey
                ],
                jsonBody: body
            )
            let response = try await service.perform(httpRequest)
            return try handleGetpaidResponse(response)
        }
    }

    /// Runs `operation` with the current access token. On 401, refreshes via
    /// `auth.invalidateAndRefresh()` and retries exactly once (PRD FR-6A.5).
    private func withAuthRetry(
        _ operation: @Sendable (_ token: String) async throws -> PayabliTransactionResult
    ) async throws -> PayabliTransactionResult {
        let firstToken = await auth.currentAccessToken()
        do {
            return try await operation(firstToken)
        } catch let err as PayabliGenericError where err.code == .tokenExpired {
            logger.info("401 received on getpaid — refreshing token and retrying once")
            let refreshed = try await auth.invalidateAndRefresh()
            return try await operation(refreshed)
        }
    }

    private func handleGetpaidResponse(_ response: PayabliResponse) throws -> PayabliTransactionResult {
        let decoder = JSONDecoder()

        // Approved (201 with Axxxx code)
        if (200..<300).contains(response.statusCode) {
            let envelope = try decoder.decode(PayabliV2TransactionEnvelope.self, from: response.body)
            guard envelope.isApproved, envelope.data != nil else {
                // Rare: 2xx with non-A code.
                throw PayabliGenericError(
                    code: .unknown,
                    reason: "Unexpected response: \(envelope.code)",
                    detail: envelope.reason
                )
            }
            return PayabliTransactionResult(from: envelope)
        }

        // Declined (402)
        if response.statusCode == 402 {
            if let decline = try? decoder.decode(PayabliDeclineError.self, from: response.body) {
                throw PayabliPaymentError.decline(decline)
            }
            throw PayabliGenericError(code: .unknown, reason: "Declined (402)")
        }

        // Validation (400)
        if response.statusCode == 400 {
            if let validation = try? decoder.decode(PayabliValidationError.self, from: response.body) {
                throw PayabliPaymentError.validation(validation)
            }
            throw PayabliGenericError(code: .unknown, reason: "Bad request (400)")
        }

        // Auth (401/403) — the outer withAuthRetry catches .tokenExpired and
        // retries once with a refreshed token.
        if response.statusCode == 401 {
            throw PayabliGenericError(code: .tokenExpired, reason: "Unauthorized (401)")
        }
        if response.statusCode == 403 {
            throw PayabliGenericError(code: .permissionDenied, reason: "Forbidden (403)")
        }

        // Server (500+)
        if response.statusCode >= 500 {
            if let server = try? decoder.decode(PayabliServerError.self, from: response.body) {
                throw PayabliPaymentError.server(server)
            }
            throw PayabliGenericError(code: .unknown, reason: "Server error (\(response.statusCode))")
        }

        throw PayabliGenericError(code: .unknown, reason: "HTTP \(response.statusCode)")
    }
}
