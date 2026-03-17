import Foundation

/// Persists failed PATCH /update calls so they can be retried on next session.
/// This is the critical safety net: if the NFC tap succeeded but the backend
/// update failed (network issue, timeout), the transaction data is not lost.
///
/// Storage: UserDefaults (lightweight, sufficient for a small queue).
/// Each entry holds the paymentTransId + raw Fiserv response dict.
public struct PendingUpdate: Sendable {
    public let paymentTransId: String
    public let fiservResponse: Data
    public let createdAt: Date

    /// Deserialize the Fiserv response back to dictionary for retry.
    var responseDict: [String: Any]? {
        try? JSONSerialization.jsonObject(with: fiservResponse) as? [String: Any]
    }
}

final class PendingUpdateQueue {

    private static let storageKey = "com.payabli.ttp.pendingUpdates"
    static let maxEntries = 50
    static let ttlSeconds: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func enqueue(paymentTransId: String, responseDict: [String: Any]) {
        var entries = loadEntries()

        guard let data = try? JSONSerialization.data(withJSONObject: responseDict) else { return }

        let entry = StoredEntry(
            paymentTransId: paymentTransId,
            fiservResponse: data,
            createdAt: Date()
        )
        entries.append(entry)
        evict(&entries)
        saveEntries(entries)
    }

    func all() -> [PendingUpdate] {
        var entries = loadEntries()
        let before = entries.count
        evict(&entries)
        if entries.count != before { saveEntries(entries) }
        return entries.map {
            PendingUpdate(
                paymentTransId: $0.paymentTransId,
                fiservResponse: $0.fiservResponse,
                createdAt: $0.createdAt
            )
        }
    }

    func remove(paymentTransId: String) {
        var entries = loadEntries()
        entries.removeAll { $0.paymentTransId == paymentTransId }
        saveEntries(entries)
    }

    var isEmpty: Bool {
        loadEntries().isEmpty
    }

    // MARK: - Persistence (Codable wrapper for UserDefaults)

    private struct StoredEntry: Codable {
        let paymentTransId: String
        let fiservResponse: Data
        let createdAt: Date
    }

    private func loadEntries() -> [StoredEntry] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let entries = try? JSONDecoder().decode([StoredEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func saveEntries(_ entries: [StoredEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Remove stale entries (older than TTL) and cap to maxEntries (keep newest).
    private func evict(_ entries: inout [StoredEntry]) {
        let cutoff = Date().addingTimeInterval(-Self.ttlSeconds)
        entries.removeAll { $0.createdAt < cutoff }
        if entries.count > Self.maxEntries {
            entries = Array(entries.suffix(Self.maxEntries))
        }
    }
}
