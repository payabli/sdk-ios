import Foundation

/// Registry that resolves a `TapToPayProvider` implementation from a provider
/// identifier (e.g. `"fiserv"`, `"apple_proximity_reader"`).
///
/// See PRD FR-11A.5..7. Providers register themselves at SDK initialization;
/// the factory is append-only — replacing a registration is allowed for tests
/// but not part of the public contract.
public final class TapToPayProviderFactory: @unchecked Sendable {
    public typealias Builder = @Sendable () -> TapToPayProvider

    public static let shared = TapToPayProviderFactory()

    private let lock = NSLock()
    private var builders: [String: Builder] = [:]

    private init() {}

    public func register(providerId: String, builder: @escaping Builder) {
        lock.lock(); defer { lock.unlock() }
        builders[providerId] = builder
    }

    public func build(providerId: String) -> TapToPayProvider? {
        lock.lock(); defer { lock.unlock() }
        return builders[providerId]?()
    }

    public func isRegistered(_ providerId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return builders[providerId] != nil
    }

    /// For tests.
    func _reset() {
        lock.lock(); defer { lock.unlock() }
        builders.removeAll()
    }
}
