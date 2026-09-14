@testable import PayabliSDKTapToPay
import XCTest

#if canImport(PayabliCardReaderCore) && canImport(ProximityReader)
    import ProximityReader

    /// What the adapter makes of the platform's reader events.
    final class TapToPayReaderEventTests: XCTestCase {
        // MARK: - Mapped

        func testProgressCarriesThePercentage() {
            XCTAssertEqual(
                FiservCardReader.mapReaderEvent(.updateProgress(42)),
                .configurationProgress(percent: 42)
            )
        }

        func testEachStateAHostActsOnIsCarried() {
            XCTAssertEqual(FiservCardReader.mapReaderEvent(.notReady), .notReady)
            XCTAssertEqual(FiservCardReader.mapReaderEvent(.cardDetected), .cardDetected)
            XCTAssertEqual(FiservCardReader.mapReaderEvent(.removeCard), .cardRemovalRequested)
            XCTAssertEqual(FiservCardReader.mapReaderEvent(.readRetry), .cardReadRetryRequested)
            XCTAssertEqual(FiservCardReader.mapReaderEvent(.pinEntryRequested), .pinEntryRequested)
            XCTAssertEqual(FiservCardReader.mapReaderEvent(.pinEntryCompleted), .pinEntryCompleted)
            XCTAssertEqual(FiservCardReader.mapReaderEvent(.userInterfaceDismissed), .promptDismissed)
        }

        // MARK: - Dropped

        /// The facade already announces a read starting, completing and
        /// failing. Carrying these as well would tell a host the same thing
        /// twice, so dropping them is the decision rather than an omission.
        func testTheStatesTheFacadeAlreadyAnnouncesAreDropped() {
            XCTAssertNil(FiservCardReader.mapReaderEvent(.readyForTap))
            XCTAssertNil(FiservCardReader.mapReaderEvent(.readCompleted))
            XCTAssertNil(FiservCardReader.mapReaderEvent(.readCancelled))
            XCTAssertNil(FiservCardReader.mapReaderEvent(.readNotCompleted))
        }

        // MARK: - The percentage is bounded

        /// The platform carries the value as a bare `Int` and documents it only
        /// as a percentage, so the range is asserted rather than trusted.
        func testAPercentageOutsideItsRangeIsBrought() {
            XCTAssertEqual(FiservCardReader.clampToPercentage(-1), 0)
            XCTAssertEqual(FiservCardReader.clampToPercentage(0), 0)
            XCTAssertEqual(FiservCardReader.clampToPercentage(100), 100)
            XCTAssertEqual(FiservCardReader.clampToPercentage(101), 100)
            XCTAssertEqual(FiservCardReader.clampToPercentage(Int.max), 100)
        }
    }

#endif
