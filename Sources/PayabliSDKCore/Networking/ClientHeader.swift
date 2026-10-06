import Foundation

/// What `X-Pyb-Client` reports about this client. The locale and the device identity are read on every
/// request, because the locale can change while the app runs.
struct ClientFacts: Sendable {
    let sdkVersion: String
    let osVersion: String
    let hardware: String
    let deviceId: @Sendable () -> String?
    var locale: @Sendable () -> String = { Locale.current.identifier(.bcp47) }

    static let none = ClientFacts(sdkVersion: PayabliCore.version, osVersion: "", hardware: "", deviceId: { nil })
}

/// The `X-Pyb-Client` value: an RFC 9651 dictionary whose members are joined by `", "`, in a fixed order,
/// so the same facts are always the same octets. A member whose value is blank, or carries a character
/// outside printable US-ASCII, is left out rather than transcoded.
enum ClientHeader {
    static let name = "X-Pyb-Client"

    static func value(of facts: ClientFacts) -> String {
        [
            string("sdk-version", facts.sdkVersion),
            "platform=ios",
            string("os-version", facts.osVersion),
            string("hardware", facts.hardware),
            string("locale", facts.locale()),
            string("device-id", facts.deviceId())
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private static func string(_ name: String, _ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespaces).isEmpty,
              value.unicodeScalars.allSatisfy({ (0x20 ... 0x7E).contains($0.value) })
        else {
            return nil
        }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\(name)=\"\(escaped)\""
    }
}

/// Stamps `X-Pyb-Client` onto every outbound request, replacing any value a caller set.
struct ClientHeaderDecoration: PayabliRequestDecoration {
    let facts: ClientFacts

    func decorate(_ request: PayabliRequest) async throws -> PayabliRequest {
        request.withHeaders([ClientHeader.name: ClientHeader.value(of: facts)])
    }
}
