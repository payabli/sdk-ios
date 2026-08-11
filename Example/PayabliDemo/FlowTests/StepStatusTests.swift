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

    func testTheDemoKnowsEverySessionStateTheSDKHas() {
        // `PayabliTTPSessionState` is `@objc`, so it cannot be `CaseIterable` and
        // the list below is written out. A tenth state fails here first.
        XCTAssertEqual(everyTapToPaySession.count, 9)
        XCTAssertNil(PayabliTTPSessionState(rawValue: 9))
    }
}

/// The nine session states, by raw value, since the enum is `@objc`.
let everyTapToPaySession: [PayabliTTPSessionState] =
    (0 ... 8).compactMap(PayabliTTPSessionState.init(rawValue:))
