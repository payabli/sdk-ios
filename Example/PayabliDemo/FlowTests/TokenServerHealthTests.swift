import XCTest

/// The failure these cover, from a real session: the token server was left on one
/// environment while the app ran on another. The app's own token was then refused
/// upstream as an invalid signature, which reads as a bad credential, and the
/// cause was found by counting characters in a token.
final class TokenServerHealthTests: XCTestCase {
    private func health(_ json: String) -> TokenServerHealth {
        TokenServerHealth(body: Data(json.utf8))
    }

    // MARK: - Agreement

    func testMatchingServerReportsHealthyAndNamesTheHost() {
        let report = health(#"{"ok":true,"upstream":"https://api.one.example/api","entry":"entryONE"}"#)
            .report(appHost: "api.one.example", appEntryPoint: "entryONE")

        XCTAssertEqual(report, "✓ Local token server healthy · api.one.example")
    }

    // MARK: - Disagreement

    func testDifferentHostIsReportedWithBothSides() {
        let report = health(#"{"ok":true,"upstream":"https://api.two.example/api","entry":"entryONE"}"#)
            .report(appHost: "api.one.example", appEntryPoint: "entryONE")

        XCTAssertTrue(report.hasPrefix("✗"), report)
        XCTAssertTrue(report.contains("serving api.two.example"), report)
        XCTAssertTrue(report.contains("app is on api.one.example"), report)
    }

    /// The right host with another paypoint still mints a token this app cannot
    /// use, so the entry point is compared too.
    func testSameHostDifferentEntryIsStillAMismatch() {
        let report = health(#"{"ok":true,"upstream":"https://api.one.example/api","entry":"entryTWO"}"#)
            .report(appHost: "api.one.example", appEntryPoint: "entryONE")

        XCTAssertTrue(report.hasPrefix("✗"), report)
        XCTAssertTrue(report.contains("entry entryTWO"), report)
        XCTAssertTrue(report.contains("app uses entryONE"), report)
        XCTAssertFalse(report.contains("serving"), "the host agrees and should not be reported")
    }

    func testBothHalvesWrongAreBothReported() {
        let report = health(#"{"ok":true,"upstream":"https://api.two.example/api","entry":"entryTHREE"}"#)
            .report(appHost: "api.one.example", appEntryPoint: "entryONE")

        XCTAssertTrue(report.contains("serving api.two.example"), report)
        XCTAssertTrue(report.contains("entry entryTHREE"), report)
    }

    // MARK: - Absent information is not a mismatch

    /// An older server answers liveness alone. Reporting that as a mismatch would
    /// cry wolf on every run against it.
    func testServerWithoutEnvironmentIsHealthyNotMismatched() {
        let report = health(#"{"ok":true}"#)
            .report(appHost: "api.one.example", appEntryPoint: "entryONE")

        XCTAssertEqual(report, "✓ Local token server healthy · environment not reported")
    }

    func testNullEntryIsNotComparedAgainstTheApp() {
        let report = health(#"{"ok":true,"upstream":"https://api.one.example/api","entry":null}"#)
            .report(appHost: "api.one.example", appEntryPoint: "entryONE")

        XCTAssertEqual(report, "✓ Local token server healthy · api.one.example")
    }

    /// A build with no entry point for its environment has nothing to compare, so
    /// the entry-point half stays silent and the missing-entry problem row on the
    /// Config screen is what reports it.
    func testAppWithoutAnEntryPointComparesOnlyTheHost() {
        let report = health(#"{"ok":true,"upstream":"https://api.one.example/api","entry":"entryONE"}"#)
            .report(appHost: "api.one.example", appEntryPoint: "")

        XCTAssertEqual(report, "✓ Local token server healthy · api.one.example")
    }

    func testUnparseableBodyIsTreatedAsNoInformation() {
        let report = health("not json at all")
            .report(appHost: "api.one.example", appEntryPoint: "entryONE")

        XCTAssertEqual(report, "✓ Local token server healthy · environment not reported")
    }

    // MARK: - Parsing

    /// The server adds the scheme when it calls, not when it reports, so a base URL
    /// configured as a bare host reaches this parser without one.
    func testSchemeLessUpstreamStillYieldsAHost() {
        let parsed = health(#"{"ok":true,"upstream":"api.two.example/api","entry":"entryONE"}"#)

        XCTAssertEqual(parsed.upstreamHost, "api.two.example")

        let report = parsed.report(appHost: "api.one.example", appEntryPoint: "entryONE")

        XCTAssertTrue(report.hasPrefix("✗"), report)
        XCTAssertTrue(report.contains("serving api.two.example"), report)
    }

    /// `URL.host` keeps the case it was given, and a resolver does not, so a base
    /// URL configured in capitals would otherwise cry wolf on every press.
    func testHostCaseIsNotAMismatch() {
        let report = health(#"{"ok":true,"upstream":"https://API.ONE.EXAMPLE/api","entry":"entryONE"}"#)
            .report(appHost: "api.one.example", appEntryPoint: "entryONE")

        XCTAssertEqual(report, "✓ Local token server healthy · API.ONE.EXAMPLE")
    }

    /// An entry point names one merchant and is compared as given.
    func testEntryPointCaseIsAMismatch() {
        let report = health(#"{"ok":true,"upstream":"https://api.one.example/api","entry":"ENTRYONE"}"#)
            .report(appHost: "api.one.example", appEntryPoint: "entryONE")

        XCTAssertTrue(report.hasPrefix("✗"), report)
        XCTAssertTrue(report.contains("entry ENTRYONE"), report)
    }

    func testUpstreamOfWhitespaceIsNoInformation() {
        let report = health(#"{"ok":true,"upstream":"   ","entry":"entryONE"}"#)
            .report(appHost: "api.one.example", appEntryPoint: "entryONE")

        XCTAssertEqual(report, "✓ Local token server healthy · environment not reported")
    }

    func testUpstreamIsComparedByHostNotByWholeURL() {
        let parsed = health(#"{"ok":true,"upstream":"https://api.one.example/api","entry":" entryONE "}"#)

        XCTAssertEqual(parsed.upstreamHost, "api.one.example", "the /api path must not defeat the compare")
        XCTAssertEqual(parsed.entry, "entryONE", "a padded entry must not read as a mismatch")
    }
}
