import Foundation

/// A card number, security code or bank account number, held so it can be overwritten.
///
/// A `String` cannot be erased: it is immutable, the runtime may move it, and nothing can say when the
/// last copy is gone. This holds the digits as bytes instead, and `close()` overwrites them.
///
/// **The guarantee starts here and runs to the socket, not from the keystroke.** Whoever supplies the
/// digits decides what they were held in before this, and a text field holds its value as a `String`,
/// which this cannot unmake: it only takes over from here. What this type adds is that the SDK keeps
/// no `String` of its own on the request path, and that the buffers it owns are overwritten once the
/// request has been written.
///
/// Not thread-safe. One value belongs to one call.
public final class SensitiveDigits: @unchecked Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// The byte `close()` writes over every digit.
    static let wipedByte: UInt8 = 0

    private var digits: [UInt8]
    private var wiped = false

    private init(_ digits: [UInt8]) {
        self.digits = digits
    }

    /// Holds a copy of the supplied digits, which the caller still owns and should overwrite in turn.
    ///
    /// - Parameter digits: the digits to hold a copy of.
    /// - Returns: the value holding a copy of `digits`.
    public static func of(_ digits: [UInt8]) -> SensitiveDigits {
        SensitiveDigits(digits)
    }

    /// For digits that are already a `String`, typically from a text field. **This cannot unmake the
    /// `String` it is given**, and no overload can: it is here because a form holds its values that way.
    ///
    /// - Parameter source: the digits as a `String`, which this cannot unmake.
    /// - Returns: the value holding the digits.
    public static func ofString(_ source: String) -> SensitiveDigits {
        SensitiveDigits(Array(source.utf8))
    }

    /// How many characters were supplied. Reads 0 after `close()`.
    public var length: Int {
        wiped ? 0 : digits.count
    }

    /// Overwrites the digits for every holder of this value. One object backs the value however many
    /// copies of it are carrying it, so closing any copy closes them all. Idempotent, so closing a
    /// value a caller already closed is not an error.
    ///
    /// After this the value behaves as empty rather than throwing: a request built from a closed value
    /// fails validation as a missing field, which is a better failure than an exception from inside a
    /// body writer.
    public func close() {
        guard !wiped else { return }
        for index in digits.indices {
            digits[index] = Self.wipedByte
        }
        wiped = true
    }

    /// The length only. The digits are what this type exists to keep out of a message.
    public var description: String {
        "SensitiveDigits(length=\(length))"
    }

    /// The same redacted text on the debug route, which `String(reflecting:)` and a debugger's `po`
    /// render. `dump()` and the variables view render the stored bytes, which no protocol redacts.
    public var debugDescription: String {
        description
    }

    /// The digits, for a rule that reads them. The handed-out array shares this value's storage rather
    /// than copying it up front: writing into it forks the storage, which leaves the value's own
    /// untouched. Empty once the value is closed.
    func read() -> [UInt8] {
        wiped ? [] : digits
    }

    /// Runs `body` over the digits this holds, filtered to the ASCII digits a request can write, with
    /// the filtered copy wiped before returning. A non-digit ASCII byte is dropped; a non-ASCII byte
    /// is refused, because a digit-shaped character from another script is not the digit it resembles.
    ///
    /// - Parameter field: the field's name, carried by the refusal when the bytes are not ASCII.
    /// - Parameter body: the rule to run over the filtered digits.
    /// - Returns: what `body` returned.
    /// - Throws: ``PayabliPayInTokenStorageError/invalidInput(_:)`` when the digits hold a non-ASCII byte.
    func useDigitBytes<T>(field: String, _ body: ([UInt8]) throws -> T) throws -> T {
        var filtered: [UInt8] = []
        filtered.reserveCapacity(digits.count)
        // Before the filter, so a refusal part-way through has wiped what it collected so far, and
        // after `body`, so a reader that kept the digits keeps its own copy, not this one.
        defer {
            for index in filtered.indices {
                filtered[index] = Self.wipedByte
            }
        }
        for byte in read() {
            guard byte < 0x80 else {
                throw PayabliPayInTokenStorageError.invalidInput("\(field) contains unsupported characters.")
            }
            if (0x30 ... 0x39).contains(byte) {
                filtered.append(byte)
            }
        }
        return try body(filtered)
    }

    /// True once `close()` has run.
    var isWiped: Bool {
        wiped
    }

    /// The backing bytes as they stand, wiped or not, so a test can assert the overwrite actually
    /// happened: `read()` answers empty once wiped, which is right for a reader and useless for proving
    /// the digits are gone.
    func rawCopy() -> [UInt8] {
        digits
    }
}

extension SensitiveDigits {
    /// The digits as text, for the host-driven path where a host encodes the method itself. The SDK's
    /// own request routes never read this: they write the digits as bytes instead, because this makes
    /// a `String`, which nothing can overwrite.
    var digitsOnly: String {
        (String(bytes: read(), encoding: .utf8) ?? "").digitsOnly
    }
}
