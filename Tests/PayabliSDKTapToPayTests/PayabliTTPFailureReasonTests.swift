import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

/// Where a failure lands, and what the state then says about it.
///
/// A landing is a remedy, so these assert the remedy a host would offer rather
/// than the error that produced it.
final class PayabliTTPFailureReasonTests: XCTestCase {
    // MARK: - The landings

    /// Both name the attestation, which is the positive match discarding the
    /// device's identity needs.
    func testAFailureThatNamesTheAttestationAsksForOne() {
        for error in [
            PayabliTTPError.attestationRevoked(reason: "x"),
            .attestationFailed(reason: "x")
        ] {
            XCTAssertEqual(
                PayabliTTPSessionState.landing(for: error, registration: .held(activationId: "dev")),
                .failed(reason: .deviceSetupRequired),
                "\(error)"
            )
        }
    }

    /// An expired token names no attestation, so it does not discard the
    /// identity. The device is as it was and the same call may work later.
    func testAnExpiredTokenDoesNotDiscardTheIdentity() {
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.tokenExpired, registration: .held(activationId: "dev")),
            .failed(reason: .serviceUnavailable)
        )
    }

    func testAnAccountThatIsNotSetUpAsksSomeoneToChangeIt() {
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.configFailed(reason: "x"), registration: .held(activationId: "dev")),
            .failed(reason: .configurationRejected)
        )
    }

    /// An OS build the reader will never run on is the device. A reader that
    /// merely would not arm is not: it leaves the device as it was.
    func testOnlyAnUnusableDeviceIsCalledIneligible() {
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.readerOSVersionNotSupported(), registration: .held(activationId: "dev")),
            .failed(reason: .deviceIneligible)
        )
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.readerSetupFailed(reason: "x"), registration: .held(activationId: "dev")),
            .failed(reason: .serviceUnavailable)
        )
    }

    /// A device owing activation is not a failure, and neither is a merchant who
    /// has not accepted terms. Each has a state of its own.
    func testWhatIsNotAFailureDoesNotLandAsOne() {
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.devicePendingActivation, registration: .held(activationId: "dev")),
            .pendingActivation(activationId: "dev")
        )
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.termsNotAccepted, registration: .held(activationId: "dev")),
            .pendingTerms
        )
    }

    /// A tap or an activation failing leaves the session where it was.
    func testAFailureThatIsNotTheSessionsMovesNothing() {
        for error in [
            PayabliTTPError.nfcFailed(reason: "x"),
            .initiateFailed(reason: "x"),
            .updateFailed(reason: "x", paymentTransId: "TXN", capture: .unknown),
            .activationFailed(reason: "x")
        ] {
            XCTAssertNil(PayabliTTPSessionState.landing(for: error, registration: .held(activationId: "dev")), "\(error)")
        }
    }

    /// A refused body is the two sides disagreeing about the contract, not a
    /// service that might answer differently in a minute: the same bytes get
    /// the same 400.
    func testARefusedBodyIsNotWorthRetrying() throws {
        // Decoded rather than constructed: the type carries no public
        // memberwise initializer, which is its own ticket.
        let refused = PayabliPaymentError.validation(
            try JSONDecoder().decode(PayabliValidationError.self, from: Data("{}".utf8))
        )

        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: refused, registration: .held(activationId: "dev")),
            .failed(reason: .sdkInternalError)
        )
    }

    func testAKeyNobodyCanVouchForLandsOnDeviceKeyUnavailable() {
        let error = TapToPayError(type: .deviceKeyUnavailable, reason: "x", detail: nil)

        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: error, registration: .held(activationId: "dev")),
            .failed(reason: .deviceKeyUnavailable)
        )
    }

    func testADeviceThatCannotBeSetUpLandsOnDeviceIneligible() {
        let error = TapToPayError(type: .deviceSetupUnsupported, reason: "x", detail: nil)

        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: error, registration: .held(activationId: "dev")),
            .failed(reason: .deviceIneligible)
        )
    }

    func testAnSDKDefectLandsOnSDKInternalErrorNotTheTransportDefault() {
        let error = TapToPayError(type: .sdkInternalError, reason: "x", detail: nil)

        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: error, registration: .held(activationId: "dev")),
            .failed(reason: .sdkInternalError)
        )
    }

    func testAnUnreachableAttestationServiceLandsOnServiceUnavailable() {
        let error = TapToPayError(type: .deviceSetupUnavailable, reason: "x", detail: nil)

        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: error, registration: .held(activationId: "dev")),
            .failed(reason: .serviceUnavailable)
        )
    }

    func testADeviceThatCannotBeIdentifiedLandsOnDeviceIneligible() {
        let error = TapToPayError(type: .deviceIdentityUnavailable, reason: "x", detail: nil)

        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: error, registration: .held(activationId: "dev")),
            .failed(reason: .deviceIneligible)
        )
    }

    /// An App ID that cannot be read is the app's configuration, which someone changes.
    func testAnAppNotConfiguredForSetupLandsOnConfigurationRejected() {
        let error = TapToPayError(type: .deviceSetupNotConfigured, reason: "x", detail: nil)

        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: error, registration: .held(activationId: "dev")),
            .failed(reason: .configurationRejected)
        )
    }

    func testALostDeviceSetupLandsOnDeviceSetupRequired() {
        let error = TapToPayError(type: .deviceSetupRequired, reason: "x", detail: nil)

        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: error, registration: .held(activationId: "dev")),
            .failed(reason: .deviceSetupRequired)
        )
    }

    /// A withdrawn setup is asked again, which is safe.
    func testAWithdrawnSetupLandsOnIdle() {
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: CancellationError(), registration: .held(activationId: "dev")),
            .idle
        )
    }

    /// A status nothing has been seen producing has no agreed meaning, so it
    /// lands where being wrong costs a retry rather than a bug report.
    func testAStatusNoRouteHasProducedIsTreatedAsTransient() {
        let burned = PayabliGenericError(type: .sessionBurned, reason: "Gone (410)")

        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: burned, registration: .held(activationId: "dev")),
            .failed(reason: .serviceUnavailable)
        )
    }

    /// Every case lands where the map says, and the whole map is here rather
    /// than a count of it.
    ///
    /// The production switch is exhaustive, so a case added to `PayabliTTPError`
    /// fails to compile until it has an arm. What this catches is the arm being
    /// changed: each pair is the remedy a host is sent to, and moving one moves
    /// a merchant.
    func testTheWholeMapLandsWhereItSays() {
        let map: [(PayabliTTPError, PayabliTTPSessionState?)] = [
            (.notInitialized, .failed(reason: .sdkInternalError)),
            (.invalidState(current: .ready, attempted: "x"), .failed(reason: .sdkInternalError)),
            (.notReady(current: .idle), .failed(reason: .sdkInternalError)),
            (.devicePendingActivation, .pendingActivation(activationId: "dev")),
            (.attestationRevoked(reason: "x"), .failed(reason: .deviceSetupRequired)),
            (.attestationFailed(reason: "x"), .failed(reason: .deviceSetupRequired)),
            (.configFailed(reason: "x"), .failed(reason: .configurationRejected)),
            (.readerSetupFailed(reason: "x"), .failed(reason: .serviceUnavailable)),
            (.nfcFailed(reason: "x"), nil),
            (.initiateFailed(reason: "x"), nil),
            (.updateFailed(reason: "x", paymentTransId: "TXN", capture: .unknown), nil),
            (.tokenExpired, .failed(reason: .serviceUnavailable)),
            (.activationFailed(reason: "x"), nil),
            (.networkError(reason: "x"), .failed(reason: .serviceUnavailable)),
            (.termsNotAccepted, .pendingTerms),
            (.readerOSVersionNotSupported(), .failed(reason: .deviceIneligible)),
            (.cardDeclined(paymentTransId: "TXN"), nil),
            (.outcomeUnknown(paymentTransId: "TXN"), nil)
        ]

        for (error, expected) in map {
            XCTAssertEqual(PayabliTTPSessionState.landing(for: error, registration: .held(activationId: "dev")), expected, "\(error)")
        }
    }

    /// Every code with a landing of its own lands there, and the map is here rather than a count of it.
    func testEveryCodeWithItsOwnLandingLandsThere() {
        let map: [(PayabliErrorType, PayabliTTPSessionState)] = [
            (.permissionDenied, .pendingActivation(activationId: "dev")),
            (.invalidConfiguration, .failed(reason: .configurationRejected)),
            (.deviceSetupNotConfigured, .failed(reason: .configurationRejected)),
            (.entryPointRefused, .failed(reason: .configurationRejected)),
            (.deviceKeyUnavailable, .failed(reason: .deviceKeyUnavailable)),
            (.deviceSetupRequired, .failed(reason: .deviceSetupRequired)),
            (.deviceSetupUnsupported, .failed(reason: .deviceIneligible)),
            (.deviceIdentityUnavailable, .failed(reason: .deviceIneligible)),
            (.deviceSetupUnavailable, .failed(reason: .serviceUnavailable)),
            (.sdkInternalError, .failed(reason: .sdkInternalError)),
            (.decodingError, .failed(reason: .sdkInternalError)),
            (.validation, .failed(reason: .sdkInternalError)),
            (.sessionBurned, .failed(reason: .serviceUnavailable))
        ]

        for (type, expected) in map {
            let error = TapToPayError(type: type, reason: "x", detail: nil)
            XCTAssertEqual(
                PayabliTTPSessionState.landing(for: error, registration: .held(activationId: "dev")),
                expected,
                "\(type)"
            )
        }
    }

    // MARK: - What the state carries

    func testTheStateCarriesTheReasonItFailedFor() {
        let state = PayabliTTPSessionState.failed(reason: .deviceIneligible)

        XCTAssertEqual(state.failureReason, .deviceIneligible)
        XCTAssertEqual(state.code, .failed)
    }

    func testAStateThatHasNotFailedCarriesNoReason() {
        XCTAssertNil(PayabliTTPSessionState.ready.failureReason)
        XCTAssertNil(PayabliTTPSessionState.initializingReader(percent: 50).failureReason)
    }

    /// The codes are what every bridge reads, so they are pinned here.
    func testTheProjectionIsStable() {
        XCTAssertEqual(PayabliTTPSessionStateCode.idle.rawValue, 0)
        XCTAssertEqual(PayabliTTPSessionStateCode.attestingDevice.rawValue, 1)
        XCTAssertEqual(PayabliTTPSessionStateCode.fetchingConfig.rawValue, 2)
        XCTAssertEqual(PayabliTTPSessionStateCode.initializingReader.rawValue, 3)
        XCTAssertEqual(PayabliTTPSessionStateCode.ready.rawValue, 4)
        XCTAssertEqual(PayabliTTPSessionStateCode.sessionExpired.rawValue, 5)
        XCTAssertEqual(PayabliTTPSessionStateCode.reinitializing.rawValue, 6)
        XCTAssertEqual(PayabliTTPSessionStateCode.pendingActivation.rawValue, 7)
        XCTAssertEqual(PayabliTTPSessionStateCode.failed.rawValue, 8)
        XCTAssertEqual(PayabliTTPSessionStateCode.pendingTerms.rawValue, 9)
        XCTAssertEqual(PayabliTTPSessionStateCode.charging.rawValue, 10)
        XCTAssertNil(PayabliTTPSessionStateCode(rawValue: 11))
    }

    /// The activities a bridge reads by integer, each at a fixed value.
    func testTheChargeActivitiesKeepTheirIntegers() {
        let expected: [TapToPayChargeActivity] = [
            .opening, .waitingForCard, .closing, .cardDetected, .cardRemovalRequested,
            .cardReadRetryRequested, .pinEntryRequested, .pinEntryCompleted, .readerPromptDismissed
        ]
        XCTAssertEqual(TapToPayChargeActivity.allCases, expected)
        for (index, activity) in expected.enumerated() {
            XCTAssertEqual(activity.rawValue, index, "\(activity)")
        }
    }

    func testTheChargingStateCarriesItsActivity() {
        let state = PayabliTTPSessionState.charging(activity: .pinEntryRequested)

        XCTAssertEqual(state.code, .charging)
        XCTAssertEqual(state.chargeActivity, .pinEntryRequested)
        XCTAssertNil(PayabliTTPSessionState.ready.chargeActivity)
    }

    /// The published vocabulary, each member at a fixed integer.
    func testThePublishedVocabularyKeepsItsIntegers() {
        XCTAssertEqual(PayabliTTPFailureReason.allCases.count, 6)
        XCTAssertEqual(PayabliTTPFailureReason.deviceSetupRequired.rawValue, 0)
        XCTAssertEqual(PayabliTTPFailureReason.configurationRejected.rawValue, 1)
        XCTAssertEqual(PayabliTTPFailureReason.serviceUnavailable.rawValue, 2)
        XCTAssertEqual(PayabliTTPFailureReason.deviceIneligible.rawValue, 3)
        XCTAssertEqual(PayabliTTPFailureReason.sdkInternalError.rawValue, 4)
        XCTAssertEqual(PayabliTTPFailureReason.deviceKeyUnavailable.rawValue, 5)
        // The bridges read these integers, so a member is appended and never
        // renumbered. This is what makes an append visible here first.
        XCTAssertNil(PayabliTTPFailureReason(rawValue: 6))
    }

    /// A transport refusal lands by its code.
    func testATransportPermissionRefusalAsksForAnActivation() {
        XCTAssertEqual(
            PayabliTTPSessionState.landing(
                for: PayabliGenericError(type: .permissionDenied, reason: "Forbidden (403)"),
                registration: .held(activationId: "dev")
            ),
            .pendingActivation(activationId: "dev")
        )
    }

    /// With no registration there is no device to activate, so the refusal is the paypoint's.
    func testARefusalWithNothingRegisteredIsTheConfiguration() {
        XCTAssertEqual(
            PayabliTTPSessionState.landing(
                for: PayabliGenericError(type: .permissionDenied, reason: "Forbidden (403)"),
                registration: .none
            ),
            .failed(reason: .configurationRejected)
        )
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.devicePendingActivation, registration: .none),
            .failed(reason: .configurationRejected)
        )
    }

    /// A registration the store could not read is the device's storage, not the paypoint's.
    func testARefusalWhoseRegistrationCannotBeReadIsTheDevicesStorage() {
        XCTAssertEqual(
            PayabliTTPSessionState.landing(
                for: PayabliGenericError(type: .permissionDenied, reason: "Forbidden (403)"),
                registration: .unreadable
            ),
            .failed(reason: .deviceKeyUnavailable)
        )
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.devicePendingActivation, registration: .unreadable),
            .failed(reason: .deviceKeyUnavailable)
        )
    }

    func testTheStateCarriesTheIdOnlyWhileActivationIsOwed() {
        XCTAssertEqual(PayabliTTPSessionState.pendingActivation(activationId: "dev").activationId, "dev")
        XCTAssertEqual(PayabliTTPSessionState.pendingActivation(activationId: "dev").code, .pendingActivation)
        XCTAssertNil(PayabliTTPSessionState.ready.activationId)
        XCTAssertNil(PayabliTTPSessionState.failed(reason: .configurationRejected).activationId)
    }
}
