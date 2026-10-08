@testable import PayabliSDKTapToPay
import XCTest

@MainActor
final class SessionManagerTests: XCTestCase {
    func testInitialStateIsIdle() {
        let sm = SessionManager()
        XCTAssertEqual(sm.sessionState, .idle)
        XCTAssertFalse(sm.isReady)
    }

    // MARK: - Valid transitions (PRD §17.2)

    func testColdPathTransitions() {
        let sm = SessionManager()
        XCTAssertTrue(sm.transition(to: .attestingDevice))
        XCTAssertTrue(sm.transition(to: .fetchingConfig))
        XCTAssertTrue(sm.transition(to: .initializingReader(percent: nil)))
        XCTAssertTrue(sm.transition(to: .ready))
        XCTAssertTrue(sm.isReady)
    }

    func testWarmPathSkipsAttestation() {
        let sm = SessionManager()
        XCTAssertTrue(sm.transition(to: .fetchingConfig))
        XCTAssertTrue(sm.transition(to: .initializingReader(percent: nil)))
        XCTAssertTrue(sm.transition(to: .ready))
    }

    func testSessionExpiredAndReinitialize() {
        let sm = SessionManager()
        _ = sm.transition(to: .fetchingConfig)
        _ = sm.transition(to: .initializingReader(percent: nil))
        _ = sm.transition(to: .ready)

        XCTAssertTrue(sm.transition(to: .sessionExpired))
        XCTAssertFalse(sm.isReady)
        XCTAssertTrue(sm.transition(to: .reinitializing))
        XCTAssertTrue(sm.transition(to: .fetchingConfig))
        XCTAssertTrue(sm.transition(to: .initializingReader(percent: nil)))
        XCTAssertTrue(sm.transition(to: .ready))
    }

    func testPendingActivationPath() {
        let sm = SessionManager()
        _ = sm.transition(to: .attestingDevice)
        XCTAssertTrue(sm.transition(to: .pendingActivation(activationId: "dev")))
        XCTAssertTrue(sm.transition(to: .idle))
    }

    // MARK: - Invalid transitions

    func testRejectsSkippingStates() {
        let sm = SessionManager()
        XCTAssertFalse(sm.transition(to: .ready))
        XCTAssertFalse(sm.transition(to: .initializingReader(percent: nil)))
        XCTAssertFalse(sm.transition(to: .sessionExpired))
    }

    func testRejectsReadyToFetching() {
        let sm = SessionManager()
        _ = sm.transition(to: .fetchingConfig)
        _ = sm.transition(to: .initializingReader(percent: nil))
        _ = sm.transition(to: .ready)
        // ready → fetchingConfig must go through sessionExpired + reinitializing.
        XCTAssertFalse(sm.transition(to: .fetchingConfig))
    }

    // MARK: - Force expiry + error

    /// The route a live caller takes: `charge()` marks a dead reader session
    /// expired from `.ready`, which the matrix already permits.
    func testReadyToSessionExpiredIsPermitted() {
        let sm = SessionManager()
        _ = sm.transition(to: .fetchingConfig)
        _ = sm.transition(to: .initializingReader(percent: nil))
        _ = sm.transition(to: .ready)
        XCTAssertTrue(sm.transition(to: .sessionExpired))
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

    func testMarkError() {
        struct DummyError: Error {}
        let sm = SessionManager()
        _ = sm.transition(to: .attestingDevice)
        sm.markError(DummyError(), registration: .none)
        XCTAssertEqual(sm.sessionState, .failed(reason: .sdkInternalError))
        XCTAssertFalse(sm.isReady)
        XCTAssertNotNil(sm.lastError)
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
                case .opening: to == .opening || to == .waitingForCard
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

    func testTheSessionIsNotReadyWhileACharges() {
        let sm = SessionManager()
        for state in [PayabliTTPSessionState.attestingDevice, .fetchingConfig, .initializingReader(percent: nil), .ready] {
            sm.transition(to: state)
        }
        XCTAssertTrue(sm.transition(to: .charging(activity: .opening)))
        XCTAssertFalse(sm.isReady)
    }
}
