import PayabliSDKCore
import XCTest

/// The lookup that pairs a paypoint with the environment the scheme chose.
///
/// A wrong pairing answers `401 "The signature key was not found"`, which reads
/// as a bad credential, so what this covers is every way the map can fail to
/// produce one rather than the happy row.
final class EntryPointLookupTests: XCTestCase {
    private let map: [String: String] = [
        "sandbox": "entryONE",
        "production": "entryTWO"
    ]

    func testEntryPointComesFromTheRunningEnvironment() {
        XCTAssertEqual(EntryPointLookup.entryPoint(from: map, for: .sandbox), "entryONE")
        XCTAssertEqual(EntryPointLookup.entryPoint(from: map, for: .production), "entryTWO")
    }

    func testEnvironmentWithNoRowHasNoEntryPointAndSaysSo() {
        let configured = ["sandbox": "entryONE"]

        XCTAssertNil(EntryPointLookup.entryPoint(from: configured, for: .production))

        let problem = EntryPointLookup.problem(from: configured, for: .production)

        XCTAssertNotNil(problem)
        XCTAssertTrue(problem?.contains("No entry point for production") == true, problem ?? "")
        XCTAssertTrue(problem?.contains("Configured: sandbox") == true, problem ?? "")
    }

    /// A row someone left blank while switching paypoints. Reported as missing
    /// rather than handed to the SDK, which would refuse it as a credential.
    func testBlankRowReadsAsMissing() {
        let blank: [String: String] = ["sandbox": "", "production": "   "]

        XCTAssertNil(EntryPointLookup.entryPoint(from: blank, for: .sandbox))
        XCTAssertNil(EntryPointLookup.entryPoint(from: blank, for: .production))
        XCTAssertNotNil(EntryPointLookup.problem(from: blank, for: .sandbox))
    }

    /// The list names environments a run could actually use, so a blank row is
    /// not offered as an alternative.
    func testBlankRowsAreNotListedAsConfigured() {
        let mixed: [String: String] = ["sandbox": "entryONE", "production": " "]

        let problem = EntryPointLookup.problem(from: mixed, for: .production)

        XCTAssertTrue(problem?.contains("Configured: sandbox.") == true, problem ?? "")
    }

    func testAnEmptyMapNamesNoAlternative() {
        let problem = EntryPointLookup.problem(from: [:], for: .sandbox)

        XCTAssertEqual(problem, "No entry point for sandbox in Secrets.entryPoints.")
    }

    /// Padding survives a copy and paste and would reach the service as part of
    /// the identifier.
    func testSurroundingWhitespaceIsTrimmed() {
        let padded = ["production": "  entryTWO\n"]

        XCTAssertEqual(EntryPointLookup.entryPoint(from: padded, for: .production), "entryTWO")
        XCTAssertNil(EntryPointLookup.problem(from: padded, for: .production))
    }
}
