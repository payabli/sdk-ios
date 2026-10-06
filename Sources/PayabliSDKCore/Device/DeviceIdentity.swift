import Foundation

package final class DeviceIdentity: @unchecked Sendable {
    private let read: @Sendable () throws -> String
    private let lock = NSLock()
    private var held: String?

    init(read: @escaping @Sendable () throws -> String) {
        self.read = read
    }

    package func value() throws -> String {
        if let held = lock.withLock({ held }) {
            return held
        }
        let value = try read()
        if !value.isEmpty {
            lock.withLock { held = value }
        }
        return value
    }
}
