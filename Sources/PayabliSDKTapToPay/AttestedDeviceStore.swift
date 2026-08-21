import Foundation
import PayabliSDKCore

/// Reads and writes the device's bindings as one stored item.
///
/// One item, because two were two writes with a window between them: a crash in
/// the gap left half an identity behind, and half an identity read as a whole one.
///
/// A read that cannot be decoded is a read that answers nothing, and the item is
/// removed on the way out. Whatever wrote it is not this version, and a device
/// that re-enrolls once is cheaper than one that trusts a shape it cannot parse.
struct AttestedDeviceStore {
    private let storage: SecureStorage
    private let logger = PayabliLogger(category: .taptopay)

    init(storage: SecureStorage) {
        self.storage = storage
        discardSuperseded()
    }

    /// The two items an install from before the bindings item may hold. Neither
    /// records the paypoint it was issued for, so neither can be adopted: a handle
    /// presented to the wrong paypoint is refused, and the refusal retires a
    /// device that was still active. The device enrolls once instead.
    private func discardSuperseded() {
        for key in PayabliKeychainKey.superseded where storage.string(forKey: key) != nil {
            logger.info("[attest] discarding an identity stored without its paypoint")
            storage.remove(forKey: key)
        }
    }

    func load() -> DeviceBindings {
        guard let raw = storage.string(forKey: PayabliKeychainKey.deviceBindings) else {
            return DeviceBindings()
        }
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DeviceBindings.self, from: data)
        else {
            logger.info("[attest] stored bindings could not be decoded; discarding")
            storage.remove(forKey: PayabliKeychainKey.deviceBindings)
            return DeviceBindings()
        }
        return decoded
    }

    /// A write that fails leaves the caller holding a binding the service has
    /// already issued, so it is reported and not raised: the session it belongs
    /// to works, and the next one re-enrolls.
    func save(_ bindings: DeviceBindings) {
        guard let data = try? JSONEncoder().encode(bindings),
              let raw = String(data: data, encoding: .utf8)
        else {
            logger.info("[attest] bindings could not be encoded")
            return
        }
        do {
            try storage.set(raw, forKey: PayabliKeychainKey.deviceBindings)
        } catch {
            logger.info("[attest] bindings could not be stored")
        }
    }
}
