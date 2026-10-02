@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// The id a host can read, answered from the binding and the key it names.
final class AppAttestServiceDeviceIdTests: XCTestCase {
    func testTheUsableIdIsNilAndTheBindingDroppedWhenItsKeyIsGone() async throws {
        for code in [2, 3] {
            let storage = InMemorySecureStorage()
            try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev", keyId: "key", in: storage)
            let (sut, attestor, _) = try AttestFixture.makeService(storage: storage)
            attestor.generateAssertionError = NSError(
                domain: AppAttestService.deviceCheckErrorDomain,
                code: code
            )

            let deviceId = try await sut.usableDeviceId(for: "myEntry")

            XCTAssertNil(deviceId, "code \(code)")
            XCTAssertNil(try sut.binding(for: "myEntry"), "code \(code)")
        }
    }

    func testTheUsableIdSurvivesAKeyCheckThatCouldNotBeMade() async throws {
        for code in [0, 1, 4] {
            let storage = InMemorySecureStorage()
            try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev", keyId: "key", in: storage)
            let (sut, attestor, _) = try AttestFixture.makeService(storage: storage)
            attestor.generateAssertionError = NSError(
                domain: AppAttestService.deviceCheckErrorDomain,
                code: code
            )

            let deviceId = try await sut.usableDeviceId(for: "myEntry")

            XCTAssertEqual(deviceId, "dev", "code \(code)")
        }
    }

    func testTheUsableIdOfAnUnregisteredEntryPointAsksThePlatformNothing() async throws {
        let (sut, attestor, _) = try AttestFixture.makeService()

        let deviceId = try await sut.usableDeviceId(for: "myEntry")

        XCTAssertNil(deviceId)
        XCTAssertEqual(attestor.generateAssertionCalls, 0)
    }

    /// The probe suspends, so the binding can be replaced while it runs, and the
    /// id read before it would name a device the store no longer holds.
    func testABindingReplacedDuringTheKeyCheckIsNotAnsweredFromTheOldRead() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_old", keyId: "key_old", in: storage)
        let (sut, attestor, _) = try AttestFixture.makeService(storage: storage)
        attestor.beforeGenerateAssertion = {
            try? sut.remember(AttestedDevice(entry: "myEntry", deviceId: "dev_new", keyId: "key_new"))
        }

        let deviceId = try await sut.usableDeviceId(for: "myEntry")

        XCTAssertNil(deviceId, "neither the read before the probe nor an unprobed replacement")
    }
}
