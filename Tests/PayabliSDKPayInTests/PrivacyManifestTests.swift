@testable import PayabliSDKPayIn
import XCTest

/// The payment form's privacy manifest declares what the payer types into it, so a store listing built on it stays true.
final class PrivacyManifestTests: XCTestCase {
    func testTheManifestDeclaresWhatThePayerEntersLinkedNotTrackedAndForFunctionality() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false, "the SDK does not track")
        let declared = try XCTUnwrap(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])

        let expectedTypes: Set = [
            "NSPrivacyCollectedDataTypePaymentInfo",
            "NSPrivacyCollectedDataTypeName",
            "NSPrivacyCollectedDataTypeEmailAddress",
            "NSPrivacyCollectedDataTypeUserID"
        ]
        XCTAssertEqual(declared.count, expectedTypes.count, "the manifest declares each collected type once")

        let declaredTypes = Set(declared.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        XCTAssertEqual(declaredTypes, expectedTypes)
        XCTAssertFalse(
            declaredTypes.contains("NSPrivacyCollectedDataTypeCrashData"),
            "the SDK installs no crash collector"
        )

        for entry in declared {
            let type = try XCTUnwrap(entry["NSPrivacyCollectedDataType"] as? String)
            XCTAssertEqual(
                Set(entry.keys),
                [
                    "NSPrivacyCollectedDataType",
                    "NSPrivacyCollectedDataTypeLinked",
                    "NSPrivacyCollectedDataTypeTracking",
                    "NSPrivacyCollectedDataTypePurposes"
                ],
                "\(type) is declared under Apple's keys, which Xcode's privacy report reads"
            )
            XCTAssertEqual(
                entry["NSPrivacyCollectedDataTypeLinked"] as? Bool,
                true,
                "\(type) is linked to the user"
            )
            XCTAssertEqual(
                entry["NSPrivacyCollectedDataTypeTracking"] as? Bool,
                false,
                "\(type) is not used for tracking"
            )
            let purposes = Set((entry["NSPrivacyCollectedDataTypePurposes"] as? [String]) ?? [])
            XCTAssertEqual(
                purposes,
                ["NSPrivacyCollectedDataTypePurposeAppFunctionality"],
                "\(type) serves the app's functionality"
            )
        }
    }
}
