@testable import PayabliSDKCore
import XCTest

/// The privacy manifest declares the data the SDK reports, so a store listing built on it stays true.
final class PrivacyManifestTests: XCTestCase {
    func testTheManifestDeclaresTheReportingDataNotLinkedNotTrackedAndForFunctionalityAndAnalytics() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let declared = try XCTUnwrap(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])

        let expectedTypes: Set = [
            "NSPrivacyCollectedDataTypeDeviceID",
            "NSPrivacyCollectedDataTypeCrashData",
            "NSPrivacyCollectedDataTypePerformanceData",
            "NSPrivacyCollectedDataTypeOtherDiagnosticData"
        ]
        XCTAssertEqual(declared.count, expectedTypes.count, "the manifest declares the reporting data")

        let declaredTypes = Set(declared.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        XCTAssertEqual(declaredTypes, expectedTypes)

        let expectedPurposes: Set = [
            "NSPrivacyCollectedDataTypePurposeAppFunctionality",
            "NSPrivacyCollectedDataTypePurposeAnalytics"
        ]
        for entry in declared {
            let type = try XCTUnwrap(entry["NSPrivacyCollectedDataType"] as? String)
            XCTAssertEqual(
                entry["NSPrivacyCollectedDataLinked"] as? Bool,
                false,
                "\(type) is not linked to the user"
            )
            XCTAssertEqual(
                entry["NSPrivacyCollectedDataTracking"] as? Bool,
                false,
                "\(type) is not used for tracking"
            )
            let purposes = Set((entry["NSPrivacyCollectedDataPurposes"] as? [String]) ?? [])
            XCTAssertEqual(purposes, expectedPurposes, "\(type) serves the app's functionality and analytics")
        }
    }
}
