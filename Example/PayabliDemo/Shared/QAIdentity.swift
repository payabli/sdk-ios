import Foundation
import UIKit

/// What this device calls itself, for a QA run where several submit at once.
///
/// Three phones and a simulator sending the sample's own test values produce rows
/// nothing can tell apart: the same customer, the same instrument, the same
/// amount, minutes apart. Every value here comes from the device, so one build
/// runs everywhere and each install still names itself.
///
/// The label is a parameter on the initialiser, so the derivation is exercised
/// against names no machine here has.
struct QAIdentity {
    let label: String
    let slug: String

    /// What a cardholder or account-holder box gets.
    ///
    /// Letters, digits and single spaces only: an account holder name must hold
    /// to that, and a model code does not. `SM-S908U1` becomes `SM S908U1`.
    var holderName: String {
        let plain = label.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return ("QA " + String(plain))
            .split(separator: " ")
            .joined(separator: " ")
    }

    var firstName: String {
        "QA"
    }

    var lastName: String {
        label
    }

    var customerNumber: String {
        "qa-ios-\(slug)"
    }

    var billingEmail: String {
        "qa+\(slug)@example.com"
    }

    /// This device, as the Configuration tab reads it back.
    var summary: String {
        "\(holderName) · \(customerNumber)"
    }

    /// The order description this sample sends, naming the device and the flow
    /// so an attempt can be told from another device's.
    func note(_ flow: String) -> String {
        "QA \(label) - \(flow)"
    }

    /// An order identifier naming this device and the moment the attempt was
    /// made.
    ///
    /// To the second, because a walk through the flows submits several a minute
    /// apart and an identifier repeated across them is one a reader cannot use.
    /// Local time, since the reader comparing it to a dashboard is in front of
    /// the device.
    func orderId(at date: Date) -> String {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        return "\(slug)-\(stamp.string(from: date))"
    }

    init(label: String) {
        let named = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = named.isEmpty ? QAIdentity.unknownLabel : named
        let slugged = QAIdentity.slug(of: candidate)

        // Punctuation alone is not blank, so the check has to come after
        // slugging rather than before it.
        if slugged.isEmpty {
            self.label = QAIdentity.unknownLabel
            slug = QAIdentity.slug(of: QAIdentity.unknownLabel)
        } else {
            self.label = candidate
            slug = slugged
        }
    }

    private static let unknownLabel = "Unknown device"

    /// This device, named the way the person watching it would name it.
    static let current = QAIdentity(label: deviceLabel())

    /// A simulator answers the name it was created with, which is what the Devices
    /// window shows. A phone answers its model instead: iOS 16 stopped handing out
    /// the owner's device name without an entitlement, so two phones of one model
    /// answer the same thing and the machine identifier is what separates them.
    private static func deviceLabel() -> String {
        if let simulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"], !simulator.isEmpty {
            return simulator
        }
        let name = UIDevice.current.name
        return name == "iPhone" || name == "iPad" ? "\(name) \(machineIdentifier())" : name
    }

    /// `iPhone15,3` and the like, which is the only per-model answer an app gets without a lookup table.
    private static func machineIdentifier() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }

    private static func slug(of label: String) -> String {
        label
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ")
            .joined(separator: "-")
    }
}
