import PayabliSDKCore
import XCTest

/// The lookup that pairs a paypoint with the environment the scheme chose.
///
/// A wrong pairing answers `401 "The signature key was not found"`, which reads
/// as a bad credential, so what this covers is every way the map can fail to
/// produce one rather than the happy row.
final class EntryPointLookupTests: XCTestCase {
    private let map: [PayabliEnvironment: String] = [
        .qa: "entryONE",
        .sandbox: "entryTWO"
    ]

    func testEntryPointComesFromTheRunningEnvironment() {
        XCTAssertEqual(EntryPointLookup.entryPoint(from: map, for: .qa), "entryONE")
        XCTAssertEqual(EntryPointLookup.entryPoint(from: map, for: .sandbox), "entryTWO")
    }

    func testEnvironmentWithNoRowHasNoEntryPointAndSaysSo() {
        XCTAssertNil(EntryPointLookup.entryPoint(from: map, for: .production))

        let problem = EntryPointLookup.problem(from: map, for: .production)

        XCTAssertNotNil(problem)
        XCTAssertTrue(problem?.contains("No entry point for production") == true, problem ?? "")
        XCTAssertTrue(problem?.contains("Configured: qa, sandbox") == true, problem ?? "")
    }

    /// A row someone left blank while switching paypoints. Reported as missing
    /// rather than handed to the SDK, which would refuse it as a credential.
    func testBlankRowReadsAsMissing() {
        let blank: [PayabliEnvironment: String] = [.qa: "", .sandbox: "   "]

        XCTAssertNil(EntryPointLookup.entryPoint(from: blank, for: .qa))
        XCTAssertNil(EntryPointLookup.entryPoint(from: blank, for: .sandbox))
        XCTAssertNotNil(EntryPointLookup.problem(from: blank, for: .qa))
    }

    /// The list names environments a run could actually use, so a blank row is
    /// not offered as an alternative.
    func testBlankRowsAreNotListedAsConfigured() {
        let mixed: [PayabliEnvironment: String] = [.qa: "entryONE", .sandbox: " "]

        let problem = EntryPointLookup.problem(from: mixed, for: .production)

        XCTAssertTrue(problem?.contains("Configured: qa.") == true, problem ?? "")
    }

    func testAnEmptyMapNamesNoAlternative() {
        let problem = EntryPointLookup.problem(from: [:], for: .qa)

        XCTAssertEqual(problem, "No entry point for qa in Secrets.entryPoints.")
    }

    /// Padding survives a copy and paste and would reach the service as part of
    /// the identifier.
    func testSurroundingWhitespaceIsTrimmed() {
        let padded: [PayabliEnvironment: String] = [.qa: "  entryONE\n"]

        XCTAssertEqual(EntryPointLookup.entryPoint(from: padded, for: .qa), "entryONE")
        XCTAssertNil(EntryPointLookup.problem(from: padded, for: .qa))
    }
}
