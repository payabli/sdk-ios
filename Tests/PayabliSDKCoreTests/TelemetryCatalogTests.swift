@testable import PayabliSDKCore
import XCTest

final class TelemetryCatalogTests: XCTestCase {
    func testEveryKeyIsOneTheServiceAccepts() throws {
        let shape = try NSRegularExpression(pattern: "^[a-z][a-z0-9_]{0,31}$")
        for property in TelemetryProperty.allCases {
            let key = property.rawValue
            let range = NSRange(key.startIndex..., in: key)
            XCTAssertNotNil(shape.firstMatch(in: key, range: range), "\(key) is not snake_case within 32 characters")
        }
    }

    func testEveryEventNameIsOneTheServiceAccepts() throws {
        let shape = try NSRegularExpression(pattern: "^[a-z][A-Za-z0-9]*(\\.[A-Za-z][A-Za-z0-9]*){1,3}$")
        for name in TelemetryCatalog.events.keys {
            let range = NSRange(name.startIndex..., in: name)
            XCTAssertNotNil(shape.firstMatch(in: name, range: range), "\(name) would be dropped by the service")
            XCTAssertLessThanOrEqual(name.count, 64, name)
        }
    }

    func testNoEventDeclaresMoreKeysThanOneEventMayCarry() {
        for (name, keys) in TelemetryCatalog.events {
            XCTAssertLessThanOrEqual(keys.count, TelemetryCatalog.maxProperties, name)
        }
    }

    func testAKeyLongerThan64CharactersIsDroppedWithItsValue() {
        let long = String(repeating: "k", count: 65)
        let edge = String(repeating: "e", count: 64)

        let kept = TelemetryCatalog.reduce([long: "1", edge: "2", "outcome": "approved"], to: [long, edge, "outcome"])

        XCTAssertEqual(kept, [edge: "2", "outcome": "approved"])
    }

    func testPairsPastTheTwentiethAreDroppedAndTheEventKeepsTwenty() {
        let keys = (1 ... 25).map { "key_\($0)" }
        let properties = Dictionary(uniqueKeysWithValues: keys.map { ($0, "v") })

        let kept = TelemetryCatalog.reduce(properties, to: Set(keys))

        XCTAssertEqual(kept.count, 20)
        XCTAssertEqual(kept, TelemetryCatalog.reduce(properties, to: Set(keys)), "the same twenty every time")
    }

    func testTheOverflowEventKeepsItsCount() {
        XCTAssertEqual(
            TelemetryCatalog.scrub(TelemetryEventName.sdkTelemetryOverflow, ["dropped": "37"]),
            ["dropped": "37"]
        )
    }
}
