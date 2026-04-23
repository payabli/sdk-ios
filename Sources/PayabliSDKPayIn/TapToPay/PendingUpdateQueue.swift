import Foundation

/// Persisted queue of transaction updates awaiting backend sync.
///
/// Backed by `UserDefaults` per PRD §22.2 — queue data is non-sensitive
/// (transaction IDs + opaque provider responses), so it doesn't need Keychain.
///
/// Constraints (PRD §21.2, FR-11E.4):
/// - Max 50 entries (FIFO eviction)
/// - 7-day TTL
/// - Forward-compatible decoding (drop corrupt entries, keep the rest)
public final class PendingUpdateQueue: @unchecked Sendable {
    public static let storageKey = "com.payabli.ttp.pendingUpdates"
    public static let maxEntries = 50
    public static let ttl: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let logger = PayabliLoggerShim()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Load / save

    public func load() -> [PendingUpdate] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return decodeForward(data: data)
    }

    public func replace(_ updates: [PendingUpdate]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(updates) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    // MARK: - Queue operations

    public func enqueue(_ update: PendingUpdate, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var current = evict(load(), now: now)
        if current.count >= Self.maxEntries {
            // FIFO — drop the oldest before inserting.
            current.removeFirst(current.count - Self.maxEntries + 1)
        }
        current.append(update)
        replace(current)
    }

    public func remove(paymentTransId: String) {
        lock.lock(); defer { lock.unlock() }
        let current = load().filter { $0.paymentTransId != paymentTransId }
        replace(current)
    }

    /// Runs TTL eviction and returns the cleaned list, persisting if anything was removed.
    public func evictExpired(now: Date = Date()) -> [PendingUpdate] {
        lock.lock(); defer { lock.unlock() }
        let current = load()
        let cleaned = evict(current, now: now)
        if cleaned.count != current.count {
            replace(cleaned)
        }
        return cleaned
    }

    // MARK: - Internal

    private func evict(_ updates: [PendingUpdate], now: Date) -> [PendingUpdate] {
        updates.filter { now.timeIntervalSince($0.createdAt) < Self.ttl }
    }

    /// Forward-compatible decoding: if the top-level array fails, drop the lot;
    /// if individual entries fail, drop those entries but keep the rest
    /// (PRD FR-11E.4).
    private func decodeForward(data: Data) -> [PendingUpdate] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try decoding as a full array first.
        if let decoded = try? decoder.decode([PendingUpdate].self, from: data) {
            return decoded
        }

        // Fall back to per-entry decoding: treat as array of raw JSON values.
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }
        var out: [PendingUpdate] = []
        for item in raw {
            if let itemData = try? JSONSerialization.data(withJSONObject: item),
               let decoded = try? decoder.decode(PendingUpdate.self, from: itemData) {
                out.append(decoded)
            }
        }
        return out
    }
}

/// Intentionally light logger shim so PendingUpdateQueue can be Sendable without
/// depending on the actor-isolated Core logger context.
private struct PayabliLoggerShim: Sendable {
    func debug(_ message: String) {}
    func warning(_ message: String) {}
}
