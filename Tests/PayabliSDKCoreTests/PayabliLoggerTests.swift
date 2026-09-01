@testable import PayabliSDKCore
import XCTest

/// The logger and the fixture that reads it.
///
/// The fixture's own cases are here rather than assumed: every case elsewhere asserts that a value is
/// *absent* from what a run wrote, and a sweep that misses somewhere a value can hide reports absence
/// for something present. No caller's assertion can tell those two apart.
final class PayabliLoggerTests: XCTestCase {
    // MARK: - The seam

    func testEachLevelReachesTheSinkWithItsMessageAndCategory() {
        let sink = RecordingLogSink()
        let logger = PayabliLogger(category: .auth, sink: sink)

        logger.debug("a debug line")
        logger.info("an info line")
        logger.warning("a warning line")
        logger.error("an error line")
        logger.fault("a fault line")

        XCTAssertEqual(
            sink.records.map(\.level),
            [.debug, .info, .warning, .error, .fault]
        )
        XCTAssertEqual(
            sink.records.map(\.message),
            ["a debug line", "an info line", "a warning line", "an error line", "a fault line"]
        )
        XCTAssertEqual(sink.records.map(\.category), Array(repeating: .auth, count: 5))
    }

    /// Swept from `allCases` rather than a list written here: a category added without a line in this
    /// test would otherwise leave both sides unchanged and the test still passing.
    func testEveryCategoryReachesTheSinkUnderItsOwnName() {
        for category in PayabliLogger.Category.allCases {
            let sink = RecordingLogSink()
            PayabliLogger(category: category, sink: sink).info("under \(category.rawValue)")

            XCTAssertEqual(sink.records.count, 1, "\(category.rawValue) wrote no record")
            XCTAssertEqual(sink.records.first?.category, category)
        }
    }

    func testTheMessageIsNotRewrittenOnTheWayToTheSink() {
        let sink = RecordingLogSink()
        // A message carrying the shapes a formatter would be tempted to touch.
        let awkward = "route=/api/v2/MoneyIn/capture [419] elapsedMs=12 \n trailing"
        PayabliLogger(category: .network, sink: sink).info(awkward)

        XCTAssertEqual(sink.records.first?.message, awkward)
    }

    // MARK: - Redaction helpers

    func testRedactKeepsOnlyTheLastFourCharacters() {
        XCTAssertEqual(PayabliLogger.redact("abcdefghij"), "[REDACTED]…ghij")
    }

    func testRedactDropsAValueTooShortToShowATail() {
        // At four characters or fewer a tail would be the whole value.
        XCTAssertEqual(PayabliLogger.redact("abcd"), "[REDACTED]")
        XCTAssertEqual(PayabliLogger.redact(""), "[REDACTED]")
    }

    func testRedactFullyDistinguishesAbsentFromPresent() {
        XCTAssertEqual(PayabliLogger.redactFully(nil), "[nil]")
        XCTAssertEqual(PayabliLogger.redactFully(""), "[REDACTED]")
        XCTAssertEqual(PayabliLogger.redactFully("a value"), "[REDACTED]")
    }

    func testNeitherHelperLeavesAnyOfTheValueBehind() {
        let secret = "SENTINEL-LOGGER-VALUE"

        XCTAssertFalse(PayabliLogger.redactFully(secret).contains(secret))
        // `redact` keeps a tail by design, so the whole value is what must not survive.
        XCTAssertFalse(PayabliLogger.redact(secret).contains(secret))
    }

    // MARK: - The fixture that reads a run

    func testAnEmptyRunIsNotReportedAsAbsence() {
        XCTAssertEqual(sweepLog(for: ["anything"], in: []), .nothingWasLogged)
    }

    func testASweepFindsAValueInAnyRecordOfTheRun() {
        let sink = RecordingLogSink()
        let logger = PayabliLogger(category: .core, sink: sink)
        logger.info("first")
        logger.info("carrying SENTINEL-BURIED here")
        logger.info("last")

        XCTAssertEqual(
            sweepLog(for: ["SENTINEL-BURIED"], in: sink.records),
            .found("SENTINEL-BURIED")
        )
    }

    func testASweepNamesWhichValueItFound() {
        let sink = RecordingLogSink()
        PayabliLogger(category: .core, sink: sink).info("carrying SENTINEL-SECOND")

        XCTAssertEqual(
            sweepLog(for: ["SENTINEL-FIRST", "SENTINEL-SECOND"], in: sink.records),
            .found("SENTINEL-SECOND")
        )
    }

    /// `redact` keeps four characters of its input, so a record carrying its output is a partial leak
    /// that a sweep for whole values reports as absence.
    func testASweepRejectsARecordCarryingOnlyTheRedactedTail() {
        let sink = RecordingLogSink()
        let credential = "SENTINEL-PARTIAL-CREDENTIAL-WXYZ"
        PayabliLogger(category: .auth, sink: sink).info(PayabliLogger.redact(credential))

        XCTAssertFalse(flattenLog(sink.records).contains(credential), "the whole value is absent")
        XCTAssertEqual(sweepLog(for: [credential], in: sink.records), .found("WXYZ"))
    }

    func testASweepOverANonEmptyRunCarryingNoneOfThemIsAbsent() {
        let sink = RecordingLogSink()
        PayabliLogger(category: .core, sink: sink).info("nothing of interest")

        XCTAssertEqual(sweepLog(for: ["SENTINEL-ABSENT"], in: sink.records), .absent)
    }

    func testTheSinkKeepsEveryRecordWrittenConcurrently() async {
        let sink = RecordingLogSink()
        let logger = PayabliLogger(category: .core, sink: sink)
        let writers = 8
        let each = 250

        await withTaskGroup(of: Void.self) { group in
            for writer in 0 ..< writers {
                group.addTask {
                    for line in 0 ..< each {
                        logger.info("writer \(writer) line \(line)")
                    }
                }
            }
        }

        XCTAssertEqual(sink.records.count, writers * each)
    }
}
