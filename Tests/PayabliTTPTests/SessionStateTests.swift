import XCTest
@testable import PayabliTTP

final class SessionStateTests: XCTestCase {

    func testIdleCanTransitionToAttesting() {
        let state = SessionState.idle
        XCTAssertTrue(state.canTransition(to: .attestingDevice))
    }

    func testIdleCannotTransitionToReady() {
        let state = SessionState.idle
        XCTAssertFalse(state.canTransition(to: .ready))
    }

    func testIdleCannotTransitionToReinitializing() {
        let state = SessionState.idle
        XCTAssertFalse(state.canTransition(to: .reinitializing))
    }

    func testAttestingCanTransitionToFetchingConfig() {
        let state = SessionState.attestingDevice
        XCTAssertTrue(state.canTransition(to: .fetchingConfig))
    }

    func testFetchingConfigCanTransitionToInitializingReader() {
        let state = SessionState.fetchingConfig
        XCTAssertTrue(state.canTransition(to: .initializingReader))
    }

    func testInitializingReaderCanTransitionToReady() {
        let state = SessionState.initializingReader
        XCTAssertTrue(state.canTransition(to: .ready))
    }

    func testReadyCanTransitionToSessionExpired() {
        let state = SessionState.ready
        XCTAssertTrue(state.canTransition(to: .sessionExpired))
    }

    func testReadyCannotTransitionToIdle() {
        let state = SessionState.ready
        XCTAssertFalse(state.canTransition(to: .idle))
    }

    func testSessionExpiredCanTransitionToReinitializing() {
        let state = SessionState.sessionExpired
        XCTAssertTrue(state.canTransition(to: .reinitializing))
    }

    func testReinitializingCanTransitionToReady() {
        let state = SessionState.reinitializing
        XCTAssertTrue(state.canTransition(to: .ready))
    }

    func testAnyStateCanTransitionToError() {
        let states: [SessionState] = [
            .idle, .attestingDevice, .fetchingConfig,
            .initializingReader, .ready, .sessionExpired, .reinitializing
        ]
        for state in states {
            XCTAssertTrue(state.canTransition(to: .error("test")), "\(state) should transition to error")
        }
    }

    func testErrorCanTransitionToIdle() {
        let state = SessionState.error("something")
        XCTAssertTrue(state.canTransition(to: .idle))
    }

    func testErrorCanTransitionToAttesting() {
        let state = SessionState.error("something")
        XCTAssertTrue(state.canTransition(to: .attestingDevice))
    }

    func testHappyPathFullCycle() {
        let transitions: [SessionState] = [
            .idle, .attestingDevice, .fetchingConfig,
            .initializingReader, .ready
        ]
        for i in 0..<transitions.count - 1 {
            XCTAssertTrue(
                transitions[i].canTransition(to: transitions[i + 1]),
                "\(transitions[i]) → \(transitions[i + 1]) should be valid"
            )
        }
    }
}
