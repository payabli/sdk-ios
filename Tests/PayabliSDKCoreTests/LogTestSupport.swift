import Foundation
@testable import PayabliSDKCore
import XCTest

// Internal rather than shipped in `PayabliSDKTestUtils`: that module is a product an integrator can
// link, so it imports the SDK plainly and sees only `public`. `LogSink` is internal, so a conformer
// can only live in a target that imports the SDK with `@testable`.

/// Records what a run wrote, so a test can read it back.
///
/// Locked because a refresh and its replay write from different tasks, and an unsynchronized append
/// loses records rather than reporting a race.
final class RecordingLogSink: LogSink, @unchecked Sendable {
    struct Record {
        let level: PayabliLogger.Level
        let category: PayabliLogger.Category
        let message: String
    }

    private let lock = NSLock()
    private var written: [Record] = []

    func write(level: PayabliLogger.Level, category: PayabliLogger.Category, message: String) {
        lock.lock()
        defer { lock.unlock() }
        written.append(Record(level: level, category: category, message: message))
    }

    var records: [Record] {
        lock.lock()
        defer { lock.unlock() }
        return written
    }
}

// MARK: - A stack whose whole log is readable

/// One sink per category, so a test can assert which category a record landed under and not only that
/// it landed.
struct LogSinks {
    let auth = RecordingLogSink()
    let network = RecordingLogSink()

    var all: [RecordingLogSink] {
        [auth, network]
    }
}

/// A stubbed stack whose auth holder, service and recovery layer all write into `sinks`.
///
/// Wiring two of the three and missing the third leaves a test reading a log the path under test never
/// wrote to, so all three are wired here and none is reachable separately.
func makeLoggingStack(
    tokenProvider: PayabliTokenRefresh? = nil,
    sinks: LogSinks
) throws -> (transport: any PayabliTransport, auth: PayabliAuth) {
    let auth = try makeTestAuth(tokenProvider: tokenProvider, sink: sinks.auth)
    return (makeAuthenticatedStack(auth: auth, sink: sinks.network), auth)
}

// MARK: - Reading a run back

/// Every message a run wrote, as one string.
func flattenLog(_ records: [RecordingLogSink.Record]) -> String {
    records.map(\.message).joined(separator: "\n")
}

/// What a sweep for a set of values found.
///
/// A path that stopped logging satisfies "the credential is not in the log" while the guarantee does
/// not hold, so `nothingWasLogged` is separate from `absent`. A Bool cannot carry the difference.
enum LogSweep: Equatable {
    case nothingWasLogged
    case found(String)
    case absent
}

/// Sweeps every message for each of `secrets` and for the last four characters of each.
///
/// `PayabliLogger.redact` keeps a four-character tail, so a record carrying its output holds part of the
/// credential while the whole value is absent, and a sweep for whole values alone reports that as
/// absence. A sentinel therefore needs a last four that appears in no message asserted present.
///
/// The head is not swept. Nothing here keeps a leading fragment, and the sentinels share their first
/// characters, so a head sweep would match one sentinel against another rather than against a leak.
///
/// A pure function, so the case that matters — an empty run reporting absence — can be driven directly
/// instead of by observing an assertion.
func sweepLog(for secrets: [String], in records: [RecordingLogSink.Record]) -> LogSweep {
    guard !records.isEmpty else { return .nothingWasLogged }
    let flattened = flattenLog(records)
    for secret in secrets {
        if flattened.contains(secret) {
            return .found(secret)
        }
        let tail = String(secret.suffix(4))
        if secret.count > 4, flattened.contains(tail) {
            return .found(tail)
        }
    }
    return .absent
}

// MARK: - Assertions

/// Asserts a specific record is present, optionally under a specific category.
///
/// This is the half that has to run first. Every absence assertion below passes on a gutted log, so
/// without an anchor naming the record the covered path is supposed to write, a test that stops
/// exercising that path keeps passing.
func assertLogged(
    _ needle: String,
    in sink: RecordingLogSink,
    category: PayabliLogger.Category? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let matching = sink.records.filter { category == nil || $0.category == category }
    let flattened = flattenLog(matching)
    XCTAssertTrue(
        flattened.contains(needle),
        "no record matching \"\(needle)\"\(category.map { " under \($0.rawValue)" } ?? "") — wrote: \(flattened)",
        file: file,
        line: line
    )
}

/// Asserts a record is absent from a category it must not reach.
func assertNotLogged(
    _ needle: String,
    in sink: RecordingLogSink,
    category: PayabliLogger.Category,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let matching = sink.records.filter { $0.category == category }
    XCTAssertFalse(
        flattenLog(matching).contains(needle),
        "\"\(needle)\" reached the \(category.rawValue) log",
        file: file,
        line: line
    )
}

/// Asserts none of `secrets` appears in anything the run wrote, across every sink handed over.
///
/// An empty run fails here. Pair it with `assertLogged` anyway: this catches a path that went silent,
/// and the anchor catches one that still writes something else.
func assertNeverLogged(
    _ secrets: [String],
    in sinks: [RecordingLogSink],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let records = sinks.flatMap(\.records)
    switch sweepLog(for: secrets, in: records) {
    case .nothingWasLogged:
        XCTFail(
            "nothing was logged, so absence proves nothing about the path under test",
            file: file,
            line: line
        )
    case let .found(secret):
        XCTFail("\"\(secret)\" reached the log: \(flattenLog(records))", file: file, line: line)
    case .absent:
        break
    }
}

/// A sink that holds the caller on one chosen occurrence of one chosen line.
///
/// The only synchronous hook inside the holder: it keeps the turn that installs a token, so another task
/// can be enqueued behind it and run before the caller waiting on that mint resumes. A case about what
/// one caller's cleanup may reach needs that order, and the holder gives no other way to build it.
///
/// `occurrence` is 1-based and exists because a holder installs its first token by acquiring one, so a
/// case about a later mint has to let the acquisition past.
///
/// That occurrence only. Every other line is let through, because the hold blocks a thread rather than
/// suspending a task: a line arriving after the release has nothing to wake it, and it would take the
/// thread with it into whatever runs next.
///
/// The hold is bounded for the same reason, so a test that never releases it fails rather than hanging.
final class HoldingLogSink: LogSink, @unchecked Sendable {
    private let held: String
    private let occurrence: Int
    private let entered: Slot<String>
    private let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var seen = 0

    init(holdingOn held: String, occurrence: Int = 1, entered: Slot<String>) {
        self.held = held
        self.occurrence = occurrence
        self.entered = entered
    }

    func write(level: PayabliLogger.Level, category: PayabliLogger.Category, message: String) {
        guard message == held else { return }
        lock.lock()
        seen += 1
        let isTheOne = seen == occurrence
        lock.unlock()
        guard isTheOne else { return }

        entered.set(message)
        _ = release.wait(timeout: .now() + 5)
    }

    func open() {
        release.signal()
    }
}
