import Foundation
import PayabliSDKCore

/// A card-present device route, named as its telemetry event names it.
enum DeviceRoute: String, Sendable {
    case challenge
    case register
    case attest
    case activate
    case config

    var completedEvent: String {
        switch self {
        case .challenge: TelemetryEventName.ttpDeviceChallengeCompleted
        case .register: TelemetryEventName.ttpDeviceRegisterCompleted
        case .attest: TelemetryEventName.ttpDeviceAttestCompleted
        case .activate: TelemetryEventName.ttpDeviceActivateCompleted
        case .config: TelemetryEventName.ttpDeviceConfigCompleted
        }
    }
}

/// The answer a measured route call received, written by the client as it reads one.
final class RouteAnswer: @unchecked Sendable {
    @TaskLocal static var current: RouteAnswer?

    private let lock = NSLock()
    private var held: PayabliResponse?

    var response: PayabliResponse? {
        get { lock.withLock { held } }
        set { lock.withLock { held = newValue } }
    }
}

/// The one client every card-present device route is sent through: the four attestation-family POSTs and the
/// configuration GET. The bearer and its refresh are the transport's.
final class DeviceServiceClient: Sendable {
    private let transport: any PayabliTransport
    private let telemetrySession: TelemetrySessionContext?
    private let logger = PayabliLogger(category: .taptopay)

    /// - Parameter transport: what every device route is sent over, the session's.
    /// - Parameter telemetrySession: the session each route call's report belongs to; `nil` for the installed one.
    init(transport: any PayabliTransport, telemetrySession: TelemetrySessionContext? = nil) {
        self.transport = transport
        self.telemetrySession = telemetrySession
    }

    /// Runs one route call and reports how it ended: `succeeded` when it returned, `refused` with the service's code
    /// when the service answered no, and `failed` when no usable answer arrived. A cancelled call reports nothing.
    ///
    /// - Parameter route: the route the call sends.
    /// - Parameter call: the request and the reading of its answer.
    /// - Returns: what `call` answered.
    func measured<Result>(_ route: DeviceRoute, _ call: () async throws -> Result) async throws -> Result {
        let answer = RouteAnswer()
        let started = ContinuousClock.now
        do {
            let result = try await RouteAnswer.$current.withValue(answer, operation: call)
            report(route, outcome: "succeeded", code: nil, since: started)
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let (outcome, code) = Self.outcome(of: error, on: route, answer: answer.response)
            report(route, outcome: outcome, code: code, since: started)
            throw error
        }
    }

    /// How a route call that threw ended.
    ///
    /// - Parameter error: what the call threw.
    /// - Parameter route: the route the call sent.
    /// - Parameter answer: the response the call read, or `nil` when none arrived.
    /// - Returns: `refused` and the code the host's error is read by when the service answered no under a code below
    ///   500, `failed` and no code otherwise. An error status is that code, whatever the envelope says.
    static func outcome(
        of error: Error,
        on route: DeviceRoute,
        answer: PayabliResponse?
    ) -> (outcome: String, code: Int?) {
        // Otherwise a refused token, a timeout and a rate limit are the transport's, not the route's answer.
        if let refusal = error as? DeviceRouteRefusal {
            return refusal.isRefusal ? ("refused", refusal.resultCode) : ("failed", nil)
        }
        guard !(error is PinnedTokenRefusal), let answer, answer.statusCode < 500,
              ![408, 429].contains(answer.statusCode)
        else { return ("failed", nil) }
        if let (code, _) = PayabliEnvelope.declineOutcome(from: answer.body) {
            let told: Int? = answer.statusCode >= 400 ? answer.statusCode : code
            if let told, told >= 500 {
                return ("failed", nil)
            }
            return ("refused", told)
        }
        // The gateway refuses `/config` with a bare 403 when the device owes its activation code.
        if route == .config, answer.statusCode == 403 {
            return ("refused", 403)
        }
        return ("failed", nil)
    }

    /// Records a route call's outcome.
    ///
    /// - Parameter route: the route the call sent.
    /// - Parameter outcome: how the call ended.
    /// - Parameter code: the service's code for a refusal.
    /// - Parameter started: when the call began.
    private func report(_ route: DeviceRoute, outcome: String, code: Int?, since started: ContinuousClock.Instant) {
        let (seconds, attoseconds) = (ContinuousClock.now - started).components
        var properties = [
            TelemetryProperty.outcome.rawValue: outcome,
            TelemetryProperty.durationMs.rawValue: String(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
        ]
        if let code {
            properties[TelemetryProperty.code.rawValue] = String(code)
        }
        if let telemetrySession {
            TelemetryRecorders.recordFor(telemetrySession, route.completedEvent, properties: properties)
        } else {
            TelemetryRecorders.record(route.completedEvent, properties: properties)
        }
    }

    /// Sends a device-route GET and answers its raw response, for the caller to classify.
    ///
    /// - Parameter route: the route sent, which names the request in its logs.
    /// - Parameter request: the request, carrying its assertion headers.
    /// - Returns: the raw response.
    func get(_ route: DeviceRoute, _ request: PayabliRequest) async throws -> PayabliResponse {
        // The headers carry the App Attest assertion, key id and device id.
        logger.info("[\(route.rawValue)] → GET \(request.path)")
        let response = try await transport.perform(request)
        RouteAnswer.current?.response = response
        // A configuration body carries the card reader's credentials. The log gets its shape.
        logger.info("[\(route.rawValue)] ← [\(response.statusCode)] bytes=\(response.body.count)")
        return response
    }

    /// Sends a device-route POST with its assertion headers and maps the answer; the bearer and refresh are the transport's.
    ///
    /// - Parameter route: the route sent, which names the request in its logs.
    /// - Parameter path: the route the request is sent to.
    /// - Parameter body: the request's body, encoded as JSON.
    /// - Parameter assertion: the assertion headers to append, or `nil` where the route needs none.
    /// - Parameter readsRefusalBeforeStatus: reads a 400, 401, 403 or 404's refusal envelope whose code is that status
    ///   before the status mapping.
    /// - Parameter isCredentialPinned: sends a refused token once and throws ``PinnedTokenRefusal``.
    /// - Parameter makeDeclineError: builds the error a refusal or decline throws, from the code and reason the
    ///   service sent, or `nil` where the words name nothing the route classifies, so the code decides.
    /// - Returns: the raw response, for the caller to decode.
    func post(
        _ route: DeviceRoute,
        path: String,
        body: some Encodable,
        assertion: AssertionHeaders?,
        readsRefusalBeforeStatus: Bool = false,
        isCredentialPinned: Bool = false,
        makeDeclineError: (_ code: Int?, _ reason: String) -> (any Error)?
    ) async throws -> PayabliResponse {
        var headers: [String: String] = [:]
        if let assertion {
            headers.merge(assertion.asDictionary) { _, new in new }
        }
        let request = try PayabliRequest.json(
            method: .post,
            path: path,
            headers: headers,
            jsonBody: body,
            isCredentialPinned: isCredentialPinned
        )

        // These bodies and headers are authentication material: `/activate`
        // carries the activation code, the others carry the App Attest key,
        // attestation and assertion. Endpoint and size only.
        logger.info("[\(route.rawValue)] → POST \(request.path) bytes=\(request.body?.count ?? 0)")

        let response: PayabliResponse
        do {
            response = try await transport.perform(request)
            RouteAnswer.current?.response = response
        } catch {
            // `AuthenticatedTransport` answers a spent token as a typed error, so
            // this catch is not only URLSession failures and not only Foundation's
            // words.
            logger.error("[\(route.rawValue)] transport error: \(ErrorSummary.of(error))")
            throw error
        }

        logger.info("[\(route.rawValue)] ← [\(response.statusCode)] bytes=\(response.body.count)")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let (code, reason) = PayabliEnvelope.declineOutcome(from: response.body, decoder: decoder),
           code == response.statusCode,
           let unregistered = AppRegistrationRefusals.hostError(status: response.statusCode, reason: reason)
        {
            logger.error("[\(route.rawValue)] refused: the app is not registered on the paypoint")
            throw unregistered
        }
        // At the statuses a refusal is sent with, an envelope naming a code is the route's refusal, read by its words only
        // when the code is the status it came with and classified by the status otherwise. Every other answer keeps the
        // transport's classification, a rate limit's wait and a refused token among them.
        if readsRefusalBeforeStatus,
           let (code, reason) = PayabliEnvelope.declineOutcome(from: response.body, decoder: decoder),
           let code, [400, 401, 403, 404].contains(response.statusCode)
        {
            logger.error("[\(route.rawValue)] refused (code=\(code))")
            if code == response.statusCode, let decline = makeDeclineError(code, reason) {
                throw DeviceRefusalStatus.carrying(response.statusCode, on: decline)
            }
            throw DeviceRouteRefusal.of(code: response.statusCode, reason: reason, httpStatus: response.statusCode)
        }
        if isCredentialPinned, response.statusCode == 401 {
            logger.error("[\(route.rawValue)] the token was refused")
            throw PinnedTokenRefusal()
        }

        do {
            try mapPayabliHTTPError(response: response)
        } catch {
            logger.error("[\(route.rawValue)] HTTP error: \(ErrorSummary.of(error))")
            throw error
        }

        if let (code, reason) = PayabliEnvelope.declineOutcome(from: response.body, decoder: decoder) {
            // The reason is the service's `resultText`, which can quote what was
            // sent. The code says which decline this was, and a classifier that
            // knows the words answers with its own failure.
            logger.error("[\(route.rawValue)] declined (code=\(code.map(String.init) ?? "nil"))")
            if let decline = makeDeclineError(code, reason) {
                throw DeviceRefusalStatus.carrying(response.statusCode, on: decline)
            }
            throw DeviceRouteRefusal.of(code: code, reason: reason, httpStatus: response.statusCode)
        }

        return response
    }
}
