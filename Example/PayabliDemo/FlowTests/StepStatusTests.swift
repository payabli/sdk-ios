import PayabliSDKTapToPay
import XCTest

/// The vocabulary the sequences are written in.
final class StepStatusTests: XCTestCase {
    func testOnlyDoneAndNotNeededReleaseTheStepAfter() {
        XCTAssertTrue(StepStatus.done.isFinished)
        XCTAssertTrue(StepStatus.notNeeded.isFinished)
        XCTAssertFalse(StepStatus.current.isFinished)
        XCTAssertFalse(StepStatus.inProgress.isFinished)
        XCTAssertFalse(StepStatus.blocked.isFinished)
        XCTAssertFalse(StepStatus.failed.isFinished)
    }

    // MARK: - The text the screens actually hold

    func testClassifyReadsTheStringsTheScreensWrite() {
        // Every screen stores the probe's outcome as display text and passes it
        // through here. The combinatorial suites construct `TokenCheck` values
        // directly, so this boundary is the one place a changed prefix would go
        // unnoticed while every invariant stayed green.
        XCTAssertEqual(TokenCheck.classify(""), .notRun)
        XCTAssertEqual(TokenCheck.classify("Checking…"), .checking)
        XCTAssertEqual(TokenCheck.classify("✓ Token endpoint returned a token"), .reachable)
        XCTAssertEqual(TokenCheck.classify("✗ Token endpoint failed: timed out"), .unreachable)
    }

    func testClassifyTreatsAnythingElseAsNotRun() {
        for text in ["checking", "Checked", "OK", "✓", "✗", " ✓ leading space", "error"] {
            let expected: TokenCheck = text == "✓" ? .reachable : text == "✗" ? .unreachable : .notRun
            XCTAssertEqual(TokenCheck.classify(text), expected, "\(text)")
        }
    }

    func testTheDemoKnowsEverySessionStateTheSDKHas() {
        // The projection is `@objc` and so cannot be `CaseIterable`; its raw
        // values are what the bridges read, so a state added to the SDK without
        // one fails here first.
        XCTAssertEqual(
            Set(everyTapToPaySession.map(\.code.rawValue)).count,
            everyTapToPaySession.count,
            "two states share a code"
        )
        for status in everyTapToPayStatus {
            if case let .unrecognised(raw) = status {
                XCTFail("the app does not name the SDK state with raw value \(raw)")
            }
        }
    }
}

/// Every session state. Written out because the enum carries payloads and
/// cannot be enumerated by raw value: a state the SDK adds and this list does
/// not is what the assertion beside it catches.
let everyTapToPaySession: [PayabliTTPSessionState] = [
    .idle,
    .attestingDevice,
    .fetchingConfig,
    .initializingReader(percent: nil),
    .ready,
    .sessionExpired,
    .reinitializing,
    .pendingActivation,
    .failed(reason: .sdkInternalError),
    .pendingTerms
]

/// The same states as this app names them.
///
/// Derived rather than written out, so a state the app has not mapped arrives here
/// as `unrecognised` and fails the assertion beside it rather than reaching a
/// screen as `state(9)`.
let everyTapToPayStatus: [TapToPaySessionStatus] =
    everyTapToPaySession.map(TapToPaySessionStatus.init)
