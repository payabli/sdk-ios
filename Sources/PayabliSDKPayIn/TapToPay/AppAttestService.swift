import Foundation
import CryptoKit
import PayabliSDKCore

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Backend wire types (PRD §8.2)

private struct ChallengeRequest: Encodable { let entry: String }
private struct ChallengeResponse: Decodable {
    let challengeId: String
    let challenge: String
}

private struct RegisterRequest: Encodable {
    let entry: String
    let keyId: String
    let hardwareId: String
    let deviceName: String
    let model: String
    let osVersion: String
    let platform: String
}
private struct RegisterResponse: Decodable {
    let deviceId: String
    let status: String?
}

private struct AttestRequest: Encodable {
    let challengeId: String
    let keyId: String
    let attestation: String
    let deviceId: String
    let appId: String
    let entry: String
    let platform: String
}

private struct ActivateRequest: Encodable {
    let entry: String
    let deviceId: String
    let activationCode: String
}

private struct ActivationChallengeRequest: Encodable {
    let entry: String
    let deviceId: String
}

private struct ActivationChallengePayload: Decodable {
    let code: String
    let expiresAt: Date?
    let alreadyIssued: Bool?
}

private struct ActivationChallengeEnvelope: Decodable {
    let responseData: ActivationChallengePayload?
}

// MARK: - AppAttestService

/// Production `DeviceAttestationService` implementation (PRD §18).
///
/// Coordinates Apple's `DCAppAttestService` with the Payabli backend:
///
/// First-run:
/// 1. `POST /challenge` (entry)                 → challengeId + challenge
/// 2. Resolve hardware identifiers
/// 3. `POST /register` → deviceId + status
/// 4. `DCAppAttestService.generateKey` → keyId (persist in Keychain)
/// 5. `DCAppAttestService.attestKey(keyId, SHA256(challenge))` → attestation
/// 6. `POST /attest` → success
///
/// Warm path: `keyId` + `deviceId` already in storage → only run step 1.
///
/// Per-request assertions (PRD §18.2) are generated on demand by
/// `generateAssertion(for:)` for `/config` and `/activate`.
public final class AppAttestService: DeviceAttestationService, @unchecked Sendable {

    private let service: PayabliService
    private let auth: PayabliAuth
    private let attestor: AppAttestor
    private let storage: SecureStorage
    private let entry: String
    private let appId: String
    private let logger = PayabliLogger(category: .taptopay)

    // Injectable hardware-identifier source so we can test on macOS.
    private let hardwareIdProvider: @Sendable () -> String
    private let deviceNameProvider: @Sendable () -> String
    private let modelProvider: @Sendable () -> String
    private let osVersionProvider: @Sendable () -> String

    public init(
        service: PayabliService,
        auth: PayabliAuth,
        attestor: AppAttestor,
        storage: SecureStorage,
        entry: String,
        appId: String,
        hardwareIdProvider: @Sendable @escaping () -> String = AppAttestService.defaultHardwareId,
        deviceNameProvider: @Sendable @escaping () -> String = AppAttestService.defaultDeviceName,
        modelProvider: @Sendable @escaping () -> String = AppAttestService.defaultModel,
        osVersionProvider: @Sendable @escaping () -> String = AppAttestService.defaultOSVersion
    ) {
        self.service = service
        self.auth = auth
        self.attestor = attestor
        self.storage = storage
        self.entry = entry
        self.appId = appId
        self.hardwareIdProvider = hardwareIdProvider
        self.deviceNameProvider = deviceNameProvider
        self.modelProvider = modelProvider
        self.osVersionProvider = osVersionProvider
    }

    // MARK: - DeviceAttestationService

    public var isAlreadyAttested: Bool {
        storage.string(forKey: PayabliKeychainKey.keyId) != nil
            && storage.string(forKey: PayabliKeychainKey.deviceId) != nil
    }

    public var cachedDeviceId: String? {
        storage.string(forKey: PayabliKeychainKey.deviceId)
    }

    public func attest(entry: String, appId: String) async throws -> AttestationResult {
        guard attestor.isSupported else {
            throw PayabliTTPError.attestationFailed(reason: "App Attest not supported on this device")
        }

        // 1. POST /challenge
        let challenge = try await postChallenge(entry: entry)

        // 2. Resolve hw identifiers
        let registerReq = RegisterRequest(
            entry: entry,
            keyId: try await resolveOrCreateKeyId(),
            hardwareId: hardwareIdProvider(),
            deviceName: deviceNameProvider(),
            model: modelProvider(),
            osVersion: osVersionProvider(),
            platform: "Ios"
        )

        // 3. POST /register
        let register = try await postRegister(registerReq)
        let isPending = register.status?.lowercased() == "pending"
        if isPending {
            logger.info("Device registered in pending state — completing attestation before prompting for activation code")
        }

        // Persist deviceId BEFORE signalling pending: `/activate` requires an
        // assertion whose headers come from keychain, and the server expects
        // `deviceId` in the `/activate` body.
        try storage.set(register.deviceId, forKey: PayabliKeychainKey.deviceId)

        // 4+5. Attest key with SHA256(challenge)
        guard let challengeData = Data(base64Encoded: challenge.challenge) ?? challenge.challenge.data(using: .utf8) else {
            throw PayabliTTPError.attestationFailed(reason: "Could not decode challenge")
        }
        let clientDataHash = Data(SHA256.hash(data: challengeData))
        let attestation = try await attestor.attestKey(registerReq.keyId, clientDataHash: clientDataHash)

        // 6. POST /attest — backend allows attesting both Active and Pending
        // devices; required to create the `DeviceAttestations` row that
        // `/activate` verifies.
        try await postAttest(AttestRequest(
            challengeId: challenge.challengeId,
            keyId: registerReq.keyId,
            attestation: attestation.base64EncodedString(),
            deviceId: register.deviceId,
            appId: appId,
            entry: entry,
            platform: "Ios"
        ))

        if isPending {
            logger.info("Attestation stored — device still pending activation")
            throw PayabliTTPError.devicePendingActivation
        }

        logger.info("Attestation completed")
        return AttestationResult(keyId: registerReq.keyId, deviceId: register.deviceId)
    }

    public func generateAssertion(for data: Data) async throws -> AssertionHeaders {
        guard let keyId = storage.string(forKey: PayabliKeychainKey.keyId),
              let deviceId = storage.string(forKey: PayabliKeychainKey.deviceId) else {
            throw PayabliTTPError.attestationFailed(reason: "Missing attestation state")
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let clientDataHash = Data(SHA256.hash(data: Data(timestamp.utf8)))
        let assertion = try await attestor.generateAssertion(keyId, clientDataHash: clientDataHash)

        return AssertionHeaders(
            assertion: assertion.base64EncodedString(),
            keyId: keyId,
            deviceId: deviceId,
            timestamp: timestamp
        )
    }

    public func requestActivationCode(entry: String) async throws -> ActivationCodeInfo {
        guard let deviceId = storage.string(forKey: PayabliKeychainKey.deviceId) else {
            throw PayabliTTPError.attestationFailed(reason: "Missing deviceId — run initialize() before requestActivationCode")
        }

        let token = await auth.currentAccessToken()
        let request = try PayabliRequest.json(
            method: .post,
            path: "/api/v2/device/taptopay/activate/challenge",
            headers: ["Authorization": "Bearer \(token)"],
            jsonBody: ActivationChallengeRequest(entry: entry, deviceId: deviceId)
        )

        let headersDump = request.headers
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: " | ")
        let bodyDump = request.body.flatMap { String(data: $0, encoding: .utf8) } ?? "<nil>"
        logger.info("[activation-challenge] → POST \(request.path)")
        logger.info("[activation-challenge] headers: \(headersDump)")
        logger.info("[activation-challenge] body: \(bodyDump)")

        let response = try await service.perform(request)
        let responseBody = String(data: response.body, encoding: .utf8) ?? "<non-utf8 \(response.body.count) bytes>"
        logger.info("[activation-challenge] ← [\(response.statusCode)] body: \(responseBody)")

        guard (200..<300).contains(response.statusCode) else {
            logger.error("[activation-challenge] HTTP error: \(response.statusCode)")
            throw PayabliTTPError.activationFailed(reason: "HTTP \(response.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let raw = try? decoder.decode(RawEnvelope.self, from: response.body),
           raw.isSuccess == false {
            let decline = try? decoder.decode(DeclineEnvelope.self, from: response.body)
            let reason = decline?.responseData?.resultText
                ?? raw.responseText
                ?? "server declined"
            let code = decline?.responseData?.resultCode
            logger.error("[activation-challenge] declined (isSuccess=false code=\(code.map(String.init) ?? "nil")): \(reason)")
            throw PayabliTTPError.activationFailed(reason: reason)
        }

        guard let envelope = try? decoder.decode(ActivationChallengeEnvelope.self, from: response.body),
              let payload = envelope.responseData else {
            throw PayabliTTPError.activationFailed(reason: "Invalid activation-challenge envelope")
        }

        return ActivationCodeInfo(
            code: payload.code,
            expiresAt: payload.expiresAt,
            alreadyIssued: payload.alreadyIssued ?? false
        )
    }

    public func activateDevice(activationCode: String, entry: String) async throws {
        guard let deviceId = storage.string(forKey: PayabliKeychainKey.deviceId) else {
            throw PayabliTTPError.attestationFailed(reason: "Missing deviceId — run initialize() before activateDevice")
        }

        // Fresh challenge
        _ = try await postChallenge(entry: entry)

        // Assertion over timestamp
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
        let assertion = try await assertionHeaders(for: Data(timestamp.utf8))
        let token = await auth.currentAccessToken()
        let request = try PayabliRequest.json(
            method: .post,
            path: "/api/v2/device/taptopay/activate",
            headers: assertion.asDictionary.merging([
                "Authorization": "Bearer \(token)"
            ]) { current, _ in current },
            jsonBody: ActivateRequest(entry: entry, deviceId: deviceId, activationCode: activationCode)
        )

        let headersDump = request.headers
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: " | ")
        let bodyDump = request.body.flatMap { String(data: $0, encoding: .utf8) } ?? "<nil>"
        logger.info("[activate] → POST \(request.path)")
        logger.info("[activate] headers: \(headersDump)")
        logger.info("[activate] body: \(bodyDump)")

        let response: PayabliResponse
        do {
            response = try await service.perform(request)
        } catch {
            logger.error("[activate] transport error: \(error.localizedDescription)")
            throw error
        }

        let responseBody = String(data: response.body, encoding: .utf8) ?? "<non-utf8 \(response.body.count) bytes>"
        logger.info("[activate] ← [\(response.statusCode)] body: \(responseBody)")

        guard (200..<300).contains(response.statusCode) else {
            logger.error("[activate] HTTP error: \(response.statusCode)")
            throw PayabliTTPError.activationFailed(reason: "HTTP \(response.statusCode)")
        }

        // The backend returns business-level failures as HTTP 200 with
        // `isSuccess: false` (see /attest, /activate). Treat those as errors.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let raw = try? decoder.decode(RawEnvelope.self, from: response.body),
           raw.isSuccess == false {
            let decline = try? decoder.decode(DeclineEnvelope.self, from: response.body)
            let reason = decline?.responseData?.resultText
                ?? raw.responseText
                ?? "server declined"
            let code = decline?.responseData?.resultCode
            logger.error("[activate] declined (isSuccess=false code=\(code.map(String.init) ?? "nil")): \(reason)")

            // Special case: the server has no active DeviceAttestations row
            // for our keyId (e.g. a previous /attest was rolled back due to
            // a paypoint misconfiguration). The cached keyId/deviceId are
            // useless; wipe them and tell the caller to re-run initialize().
            if code == 401 {
                logger.error("[activate] clearing local attestation cache and signaling attestationRevoked")
                clearCache()
                throw PayabliTTPError.attestationRevoked(reason: reason)
            }

            throw PayabliTTPError.activationFailed(reason: reason)
        }
    }

    public func clearCache() {
        storage.remove(forKey: PayabliKeychainKey.keyId)
        storage.remove(forKey: PayabliKeychainKey.deviceId)
    }

    // MARK: - Internals

    /// Generic decline/error payload shape returned when `isSuccess == false`.
    /// The backend does not use HTTP error codes for business-level failures —
    /// it returns HTTP 200 with this shape instead, so every caller must
    /// inspect `isSuccess` in addition to the HTTP status.
    private struct DeclinePayload: Decodable {
        let resultCode: Int?
        let resultText: String?
    }

    /// Decodes the top-level envelope without committing to a shape for
    /// `responseData` (different shapes apply to success vs decline). Used as
    /// a pre-pass to detect `isSuccess: false` and surface the server-side
    /// reason without failing on "can't decode responseData".
    private struct RawEnvelope: Decodable {
        let isSuccess: Bool?
        let responseText: String?
    }

    /// Envelope used when `isSuccess == true`. `responseData` decodes into the
    /// caller-provided payload type.
    private struct SuccessEnvelope<Payload: Decodable>: Decodable {
        let responseData: Payload?
    }

    /// Shape of `responseData` on decline responses (used to extract a useful
    /// server-side message when `isSuccess: false`).
    private struct DeclineEnvelope: Decodable {
        let responseData: DeclinePayload?
    }

    private func postChallenge(entry: String) async throws -> ChallengeResponse {
        let data: ChallengeResponse? = try await postAttestationRequest(
            path: "/api/v2/device/taptopay/challenge",
            body: ChallengeRequest(entry: entry),
            label: "challenge"
        )
        guard let data else {
            throw PayabliTTPError.attestationFailed(reason: "challenge missing responseData")
        }
        return data
    }

    private func postRegister(_ body: RegisterRequest) async throws -> RegisterResponse {
        let data: RegisterResponse? = try await postAttestationRequest(
            path: "/api/v2/device/taptopay/register",
            body: body,
            label: "register"
        )
        guard let data else {
            throw PayabliTTPError.attestationFailed(reason: "register missing responseData")
        }
        return data
    }

    private struct EmptyPayload: Decodable {}
    private func postAttest(_ body: AttestRequest) async throws {
        let _: EmptyPayload? = try await postAttestationRequest(
            path: "/api/v2/device/taptopay/attest",
            body: body,
            label: "attest"
        )
    }

    /// Issues an authenticated POST to an attestation endpoint and returns the
    /// decoded `responseData` on success. Treats `isSuccess == false` as an
    /// error even when the HTTP status is 200 (the backend returns
    /// business-level failures as HTTP 200 with `isSuccess: false` +
    /// `responseData.resultCode`/`resultText`). Logs request + response
    /// details. Always uses the current access token held by `PayabliAuth`;
    /// no token chaining.
    private func postAttestationRequest<Body: Encodable, Payload: Decodable>(
        path: String,
        body: Body,
        label: String
    ) async throws -> Payload? {
        let token = await auth.currentAccessToken()
        let request = try PayabliRequest.json(
            method: .post,
            path: path,
            headers: ["Authorization": "Bearer \(token)"],
            jsonBody: body
        )

        let headersDump = request.headers
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: " | ")
        let bodyDump = request.body.flatMap { String(data: $0, encoding: .utf8) } ?? "<nil>"
        logger.info("[\(label)] → POST \(request.path)")
        logger.info("[\(label)] headers: \(headersDump)")
        logger.info("[\(label)] body: \(bodyDump)")

        let response: PayabliResponse
        do {
            response = try await service.perform(request)
        } catch {
            logger.error("[\(label)] transport error: \(error.localizedDescription)")
            throw error
        }

        let responseBody = String(data: response.body, encoding: .utf8) ?? "<non-utf8 \(response.body.count) bytes>"
        logger.info("[\(label)] ← [\(response.statusCode)] body: \(responseBody)")

        do {
            try service.mapHTTPError(response: response)
        } catch {
            logger.error("[\(label)] HTTP error: \(error.localizedDescription)")
            throw error
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let raw: RawEnvelope
        do {
            raw = try decoder.decode(RawEnvelope.self, from: response.body)
        } catch {
            logger.error("[\(label)] envelope decode failed: \(error.localizedDescription)")
            throw PayabliTTPError.attestationFailed(reason: "Failed to decode \(label) envelope")
        }

        if raw.isSuccess == false {
            let decline = try? decoder.decode(DeclineEnvelope.self, from: response.body)
            let reason = decline?.responseData?.resultText
                ?? raw.responseText
                ?? "server declined"
            let code = decline?.responseData?.resultCode
            logger.error("[\(label)] declined (isSuccess=false code=\(code.map(String.init) ?? "nil")): \(reason)")
            throw PayabliTTPError.attestationFailed(reason: "\(label) declined — \(reason)")
        }

        do {
            let success = try decoder.decode(SuccessEnvelope<Payload>.self, from: response.body)
            return success.responseData
        } catch {
            logger.error("[\(label)] payload decode failed: \(error.localizedDescription)")
            throw PayabliTTPError.attestationFailed(reason: "Failed to decode \(label) response")
        }
    }

    private func resolveOrCreateKeyId() async throws -> String {
        if let existing = storage.string(forKey: PayabliKeychainKey.keyId) {
            return existing
        }
        let keyId = try await attestor.generateKey()
        try storage.set(keyId, forKey: PayabliKeychainKey.keyId)
        return keyId
    }

    private func assertionHeaders(for data: Data) async throws -> AssertionHeaders {
        try await generateAssertion(for: data)
    }

    // MARK: - Default hardware identifier providers

    public static var defaultHardwareId: @Sendable () -> String {
        {
            #if canImport(UIKit)
            return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            #else
            return UUID().uuidString
            #endif
        }
    }

    public static var defaultDeviceName: @Sendable () -> String {
        {
            #if canImport(UIKit)
            return UIDevice.current.name
            #else
            return "macOS"
            #endif
        }
    }

    public static var defaultModel: @Sendable () -> String {
        {
            var sysinfo = utsname()
            uname(&sysinfo)
            let raw = withUnsafePointer(to: &sysinfo.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
            }
            return raw.trimmingCharacters(in: .controlCharacters)
        }
    }

    public static var defaultOSVersion: @Sendable () -> String {
        {
            #if canImport(UIKit)
            return UIDevice.current.systemVersion
            #else
            return ProcessInfo.processInfo.operatingSystemVersionString
            #endif
        }
    }
}
