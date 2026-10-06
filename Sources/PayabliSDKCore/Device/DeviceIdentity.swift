import Foundation

package final class DeviceIdentity: @unchecked Sendable {
    private let read: @Sendable () throws -> String
    private let lock = NSLock()
    private var held: String?

    init(read: @escaping @Sendable () throws -> String) {
        self.read = read
    }

    package func value() throws -> String {
        try lock.withLock {
            if let held {
                return held
            }
            let value = try read()
            if !value.isEmpty {
                held = value
            }
            return value
        }
    }
}
