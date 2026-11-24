@testable import PayabliSDKTapToPay
import XCTest

@MainActor
final class SessionManagerTests: XCTestCase {
    func testInitialStateIsIdle() {
        let sm = SessionManager()
        XCTAssertEqual(sm.sessionState, .idle)
        XCTAssertFalse(sm.isReady)
    }

    func testAnActivationSetupDescribesItselfWithoutItsCode() {
        let kind = SessionSetupKind.activate(code: "798916")
        XCTAssertFalse("\(kind)".contains("798916"))
        XCTAssertFalse(String(reflecting: kind).contains("798916"))
        XCTAssertNotEqual(kind, .activate(code: "000000"))
    }

    // MARK: - Valid transitions

    func testColdPathTransitions() {
        let sm = SessionManager()
        XCTAssertNoThrow(try sm.advance(to: .attestingDevice))
        XCTAssertNoThrow(try sm.advance(to: .fetchingConfig))
        XCTAssertNoThrow(try sm.advance(to: .initializingReader(percent: nil)))
        XCTAssertNoThrow(try sm.advance(to: .ready))
        XCTAssertTrue(sm.isReady)
    }

    func testWarmPathSkipsAttestation() {
        let sm = SessionManager()
        XCTAssertNoThrow(try sm.advance(to: .fetchingConfig))
        XCTAssertNoThrow(try sm.advance(to: .initializingReader(percent: nil)))
        XCTAssertNoThrow(try sm.advance(to: .ready))
    }

    func testSessionExpiredAndReinitialize() throws {
        let sm = SessionManager()
        try sm.advance(to: .fetchingConfig)
        try sm.advance(to: .initializingReader(percent: nil))
        try sm.advance(to: .ready)

        XCTAssertNoThrow(try sm.advance(to: .sessionExpired))
        XCTAssertFalse(sm.isReady)
        XCTAssertNoThrow(try sm.advance(to: .reinitializing))
        XCTAssertNoThrow(try sm.advance(to: .fetchingConfig))
        XCTAssertNoThrow(try sm.advance(to: .initializingReader(percent: nil)))
        XCTAssertNoThrow(try sm.advance(to: .ready))
    }

    func testPendingActivationPath() throws {
        let sm = SessionManager()
        try sm.advance(to: .attestingDevice)
        XCTAssertNoThrow(try sm.advance(to: .pendingActivation(activationId: "dev")))
        XCTAssertNoThrow(try sm.advance(to: .idle))
    }

    // MARK: - Invalid transitions

    func testRejectsSkippingStates() {
        let sm = SessionManager()
        XCTAssertThrowsError(try sm.advance(to: .ready))
        XCTAssertThrowsError(try sm.advance(to: .initializingReader(percent: nil)))
        XCTAssertThrowsError(try sm.advance(to: .sessionExpired))
    }

    func testRejectsReadyToFetching() throws {
        let sm = SessionManager()
        try sm.advance(to: .fetchingConfig)
        try sm.advance(to: .initializingReader(percent: nil))
        try sm.advance(to: .ready)
        // ready → fetchingConfig must go through sessionExpired + reinitializing.
        XCTAssertThrowsError(try sm.advance(to: .fetchingConfig))
    }

    func testARefusedAdvanceThrowsNamingBothStatesAndReportsNothing() throws {
        let sm = SessionManager()
        try sm.advance(to: .fetchingConfig)
        try sm.advance(to: .initializingReader(percent: nil))
        try sm.advance(to: .ready)
        var count = 0
        sm.onMove = { _, _ in count += 1 }

        XCTAssertThrowsError(try sm.advance(to: .fetchingConfig)) { error in
            let refused = error as? RefusedSessionMove
            XCTAssertEqual(refused?.from, "ready")
            XCTAssertEqual(refused?.to, "fetching_config")
        }
        XCTAssertEqual(sm.sessionState, .ready)
        XCTAssertEqual(count, 0)
    }

    // MARK: - Expiry and failure

    /// The route a live caller takes: `charge()` marks a dead reader session
    /// expired from `.ready`, which the matrix already permits.
    func testReadyToSessionExpiredIsPermitted() throws {
        let sm = SessionManager()
        try sm.advance(to: .fetchingConfig)
        try sm.advance(to: .initializingReader(percent: nil))
        try sm.advance(to: .ready)
        XCTAssertNoThrow(try sm.advance(to: .sessionExpired))
        XCTAssertEqual(sm.sessionState, .sessionExpired)
        XCTAssertFalse(sm.isReady)
    }

    /// Starting over has to be reachable from every state, because
    /// `initialize()` is the documented way back and can be called from any of
    /// them. Before this, `.ready` and `.sessionExpired` could not reach `.idle`
    /// and `reset()` assigned the state directly to get around it.
    func testEveryStateCanStartOver() {
        let states: [PayabliTTPSessionState] = [
            .idle, .attestingDevice, .fetchingConfig, .initializingReader(percent: nil),
            .ready, .sessionExpired, .reinitializing, .pendingActivation(activationId: "dev"),
            .failed(reason: .sdkInternalError), .pendingTerms, .charging(activity: .waitingForCard)
        ]
        for state in states {
            XCTAssertTrue(
                SessionManager.isValidTransition(from: state, to: .idle),
                "\(state) cannot start over"
            )
        }
    }

    func testResetClearsTheLastError() {
        struct DummyError: Error {}
        let sm = SessionManager()
        sm.markError(DummyError(), registration: .none)
        sm.reset()
        XCTAssertEqual(sm.sessionState, .idle)
        XCTAssertFalse(sm.isReady)
        XCTAssertNil(sm.lastError)
    }

    func testMarkError() throws {
        struct DummyError: Error {}
        let sm = SessionManager()
        try sm.advance(to: .attestingDevice)
        sm.markError(DummyError(), registration: .none)
        XCTAssertEqual(sm.sessionState, .failed(reason: .sdkInternalError))
        XCTAssertFalse(sm.isReady)
        XCTAssertNotNil(sm.lastError)
    }

    func testAFailureLandsOnlyOnAnEdgeTheTableDeclares() throws {
        let sm = SessionManager()
        try sm.advance(to: .fetchingConfig)
        try sm.advance(to: .initializingReader(percent: nil))
        try sm.advance(to: .ready)
        var count = 0
        sm.onMove = { _, _ in count += 1 }

        sm.markError(PayabliTTPError.devicePendingActivation(httpStatus: 403), registration: .held(activationId: "dev"))

        XCTAssertEqual(sm.sessionState, .ready)
        XCTAssertEqual(count, 0)
        XCTAssertNotNil(sm.lastError)
    }

    func testEveryStateCanFail() {
        let states: [PayabliTTPSessionState] = [
            .idle, .attestingDevice, .fetchingConfig, .initializingReader(percent: nil),
            .ready, .sessionExpired, .reinitializing, .pendingActivation(activationId: "dev"),
            .failed(reason: .sdkInternalError), .pendingTerms, .charging(activity: .waitingForCard)
        ]
        for state in states {
            XCTAssertTrue(
                SessionManager.isValidTransition(from: state, to: .failed(reason: .serviceUnavailable)),
                "\(state) cannot fail"
            )
        }
    }

    /// The terms state is reached from the reader phase and leaves the way `pendingActivation` does:
    /// the host resolves what the session waits on, then initializes again from attestation.
    func testPendingTermsIsEnteredFromTheReaderPhaseAndLeavesToAttestation() {
        XCTAssertTrue(SessionManager.isValidTransition(from: .initializingReader(percent: nil), to: .pendingTerms))
        XCTAssertTrue(SessionManager.isValidTransition(from: .pendingTerms, to: .attestingDevice))
        XCTAssertTrue(SessionManager.isValidTransition(from: .pendingTerms, to: .idle))
    }

    /// It is not a way into the reader being usable: only a fresh run gets there.
    func testPendingTermsDoesNotReachReadyDirectly() {
        XCTAssertFalse(SessionManager.isValidTransition(from: .pendingTerms, to: .ready))
        XCTAssertFalse(SessionManager.isValidTransition(from: .ready, to: .pendingTerms))
    }

    // MARK: - Charging

    func testAChargeStartsFromReadyByOpening() {
        for activity in TapToPayChargeActivity.allCases {
            XCTAssertEqual(
                SessionManager.isValidTransition(from: .ready, to: .charging(activity: activity)),
                activity == .opening,
                "ready -> \(activity)"
            )
        }
    }

    func testOnlyReadyStartsACharge() {
        let others: [PayabliTTPSessionState] = [
            .idle, .attestingDevice, .fetchingConfig, .initializingReader(percent: nil), .sessionExpired,
            .reinitializing, .pendingActivation(activationId: "dev"), .failed(reason: .sdkInternalError), .pendingTerms
        ]
        for state in others {
            XCTAssertFalse(SessionManager.isValidTransition(from: state, to: .charging(activity: .opening)), "\(state)")
        }
    }

    /// Opening leads to the wait, the wait and the reader's prompts lead to each other and to closing, and
    /// closing leads to no other activity.
    func testAChargeMovesForwardThroughItsActivities() {
        for from in TapToPayChargeActivity.allCases {
            for to in TapToPayChargeActivity.allCases {
                let expected: Bool = switch from {
                case .opening: to == .opening || to == .waitingForCard || to == .closing
                case .closing: to == .closing
                default: to != .opening
                }
                XCTAssertEqual(
                    SessionManager.isValidTransition(from: .charging(activity: from), to: .charging(activity: to)),
                    expected,
                    "\(from) -> \(to)"
                )
            }
        }
    }

    func testEveryActivityCanEndTheCharge() {
        for activity in TapToPayChargeActivity.allCases {
            let charging = PayabliTTPSessionState.charging(activity: activity)
            XCTAssertTrue(SessionManager.isValidTransition(from: charging, to: .ready), "\(activity)")
            XCTAssertTrue(SessionManager.isValidTransition(from: charging, to: .sessionExpired), "\(activity)")
            XCTAssertFalse(SessionManager.isValidTransition(from: charging, to: .fetchingConfig), "\(activity)")
        }
    }

    /// A charge that outlived a rebuilt session leaves the new charge alone.
    func testAnEndedChargeLeavesTheNextChargeAlone() throws {
        let sm = SessionManager()
        for state in [PayabliTTPSessionState.attestingDevice, .fetchingConfig, .initializingReader(percent: nil), .ready] {
            try sm.advance(to: state)
        }
        let first = try XCTUnwrap(sm.beginCharge())
        for state in [PayabliTTPSessionState.idle, .attestingDevice, .fetchingConfig, .initializingReader(percent: nil), .ready] {
            try sm.advance(to: state)
        }
        let second = try XCTUnwrap(sm.beginCharge())

        sm.recordChargeActivity(.closing, for: first)
        sm.endCharge(first)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(sm.sessionState, .charging(activity: .opening))
        XCTAssertFalse(sm.isReady)
        XCTAssertNil(sm.beginCharge(), "a third charge was let in while the second held the reader")
    }

    func testTheSessionIsNotReadyDuringACharge() throws {
        let sm = SessionManager()
        for state in [PayabliTTPSessionState.attestingDevice, .fetchingConfig, .initializingReader(percent: nil), .ready] {
            try sm.advance(to: state)
        }
        XCTAssertNoThrow(try sm.advance(to: .charging(activity: .opening)))
        XCTAssertFalse(sm.isReady)
    }
}
