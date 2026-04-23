import XCTest
@testable import PayabliSDKPayIn

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
        XCTAssertTrue(sm.transition(to: .initializingReader))
        XCTAssertTrue(sm.transition(to: .ready))
        XCTAssertTrue(sm.isReady)
    }

    func testWarmPathSkipsAttestation() {
        let sm = SessionManager()
        XCTAssertTrue(sm.transition(to: .fetchingConfig))
        XCTAssertTrue(sm.transition(to: .initializingReader))
        XCTAssertTrue(sm.transition(to: .ready))
    }

    func testSessionExpiredAndReinitialize() {
        let sm = SessionManager()
        _ = sm.transition(to: .fetchingConfig)
        _ = sm.transition(to: .initializingReader)
        _ = sm.transition(to: .ready)

        XCTAssertTrue(sm.transition(to: .sessionExpired))
        XCTAssertFalse(sm.isReady)
        XCTAssertTrue(sm.transition(to: .reinitializing))
        XCTAssertTrue(sm.transition(to: .fetchingConfig))
        XCTAssertTrue(sm.transition(to: .initializingReader))
        XCTAssertTrue(sm.transition(to: .ready))
    }

    func testPendingActivationPath() {
        let sm = SessionManager()
        _ = sm.transition(to: .attestingDevice)
        XCTAssertTrue(sm.transition(to: .pendingActivation))
        XCTAssertTrue(sm.transition(to: .idle))
    }

    // MARK: - Invalid transitions

    func testRejectsSkippingStates() {
        let sm = SessionManager()
        XCTAssertFalse(sm.transition(to: .ready))
        XCTAssertFalse(sm.transition(to: .initializingReader))
        XCTAssertFalse(sm.transition(to: .sessionExpired))
    }

    func testRejectsReadyToFetching() {
        let sm = SessionManager()
        _ = sm.transition(to: .fetchingConfig)
        _ = sm.transition(to: .initializingReader)
        _ = sm.transition(to: .ready)
        // ready → fetchingConfig must go through sessionExpired + reinitializing.
        XCTAssertFalse(sm.transition(to: .fetchingConfig))
    }

    // MARK: - Force expiry + error

    func testForceSessionExpiry() {
        let sm = SessionManager()
        _ = sm.transition(to: .fetchingConfig)
        _ = sm.transition(to: .initializingReader)
        _ = sm.transition(to: .ready)
        sm.forceSessionExpiry()
        XCTAssertEqual(sm.sessionState, .sessionExpired)
        XCTAssertFalse(sm.isReady)
    }

    func testMarkError() {
        struct DummyError: Error {}
        let sm = SessionManager()
        _ = sm.transition(to: .attestingDevice)
        sm.markError(DummyError())
        XCTAssertEqual(sm.sessionState, .error)
        XCTAssertFalse(sm.isReady)
        XCTAssertNotNil(sm.lastError)
    }
}
