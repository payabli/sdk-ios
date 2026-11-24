import Foundation
@testable import PayabliSDKCore
import XCTest

/// Records every line written, so a test can assert what a log never carries.
final class LogLineSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var lines: [String] {
        lock.withLock { recorded }
    }

    var logger: PayabliLogger {
        PayabliLogger(category: .taptopay, sink: self)
    }

    func write(level _: PayabliLogger.Level, category _: PayabliLogger.Category, message: String) {
        lock.withLock { recorded.append(message) }
    }
}

/// Answers every request the same way, and keeps what it was sent.
final class RecordingRouteTransport: PayabliTransport, @unchecked Sendable {
    enum Answer: Sendable {
        case status(Int, body: Data)
        case error(any Error)
    }

    private let answer: Answer
    private let lock = NSLock()
    private var requests: [PayabliRequest] = []

    init(answer: Answer) {
        self.answer = answer
    }

    var sent: [PayabliRequest] {
        lock.withLock { requests }
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        lock.withLock { requests.append(request) }
        switch answer {
        case let .status(code, body): return PayabliResponse(statusCode: code, headers: [:], body: body)
        case let .error(error): throw error
        }
    }

    func performV2<T: Decodable & Sendable>(_: PayabliRequest, decoding _: T.Type) async throws -> PayabliV2Envelope<T> {
        throw URLError(.unsupportedURL)
    }
}

/// Asserts a line containing `needle` was written. Run it before ``assertNoneLogged(_:in:file:line:)``, which passes on a
/// path that went silent.
func assertLineLogged(_ needle: String, in sink: LogLineSink, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(
        sink.lines.contains { $0.contains(needle) },
        "no record matching \"\(needle)\" — wrote: \(sink.lines)",
        file: file,
        line: line
    )
}

/// Asserts that something was written and that none of `values` appears in any line, whole or as the four-character
/// tail `PayabliLogger.redact` keeps.
func assertNoneLogged(_ values: [String], in sink: LogLineSink, file: StaticString = #filePath, line: UInt = #line) {
    let lines = sink.lines
    XCTAssertFalse(lines.isEmpty, "nothing was logged, so absence proves nothing", file: file, line: line)
    for value in values {
        for needle in [value, String(value.suffix(4))] {
            XCTAssertFalse(lines.contains { $0.contains(needle) }, "\"\(needle)\" reached the log: \(lines)", file: file, line: line)
        }
    }
}
