@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

final class DeviceIdentityTests: XCTestCase {
    private struct Unreadable: Error {}

    func testAValueReadIsKeptAndTheStoreIsNotAskedAgain() throws {
        let reads = ReadCount()
        let identity = DeviceIdentity {
            reads.increment()
            return "5f9125ec0ed0e7e2052aa6a6e3130778"
        }

        XCTAssertEqual(try identity.value(), "5f9125ec0ed0e7e2052aa6a6e3130778")
        XCTAssertEqual(try identity.value(), "5f9125ec0ed0e7e2052aa6a6e3130778")
        XCTAssertEqual(reads.count, 1)
    }

    func testConcurrentFirstReadsReadTheStoreOnce() {
        let reads = ReadCount()
        let identity = DeviceIdentity {
            reads.increment()
            Thread.sleep(forTimeInterval: 0.01)
            return "5f9125ec0ed0e7e2052aa6a6e3130778"
        }

        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            _ = try? identity.value()
        }

        XCTAssertEqual(reads.count, 1)
    }

    /// Before the first unlock the store refuses, and after it the same reader answers.
    func testAStoreThatRefusedIsAskedAgain() throws {
        let storage = InMemorySecureStorage()
        storage.readFailure = Unreadable()
        let session = try PayabliSession(
            config: PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "t" }),
            deviceIdentity: DeviceIdentity { try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: "com.acme.checkout") }
        )

        XCTAssertNil(session.deviceId)
        XCTAssertThrowsError(try session.deviceIdentity.value())

        storage.readFailure = nil

        XCTAssertEqual(session.deviceId?.count, 32)
    }

    func testNothingToBuildFromIsNilOnTheSessionAndBlankBeneathIt() throws {
        let session = try PayabliSession(
            config: PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "t" }),
            deviceIdentity: DeviceIdentity { "" }
        )

        XCTAssertNil(session.deviceId)
        XCTAssertEqual(try session.deviceIdentity.value(), "")
    }

    func testTheModelIsThePlatformHardwareCode() {
        let model = DeviceModel.hardware()

        XCTAssertFalse(model.isEmpty)
        XCTAssertEqual(model, model.trimmingCharacters(in: .controlCharacters))
    }
}

private final class ReadCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock { value += 1 }
    }
}
