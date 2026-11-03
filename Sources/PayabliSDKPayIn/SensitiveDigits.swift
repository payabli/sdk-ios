import Foundation

/// A card number, security code or account number as bytes `close()` overwrites, since a `String` can't be.
/// The host's own `String` stays as it is; the SDK keeps no copy of its own once a request is written.
/// Not thread-safe: one value belongs to one call.
final class SensitiveDigits: @unchecked Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// The byte `close()` writes over every digit.
    static let wipedByte: UInt8 = 0

    private var digits: [UInt8]
    private var wiped = false

    private init(_ digits: [UInt8]) {
        self.digits = digits
    }

    /// The last holder going away overwrites the digits, so a value nobody closed doesn't leave them behind.
    deinit {
        close()
    }

    /// Holds a copy of the supplied digits, which the caller still owns and should overwrite in turn.
    ///
    /// - Parameter digits: the digits to hold a copy of.
    /// - Returns: the value holding a copy of `digits`.
    static func of(_ digits: [UInt8]) -> SensitiveDigits {
        SensitiveDigits(digits)
    }

    /// For digits that are already a `String`, typically from a text field. **This cannot unmake the
    /// `String` it is given**, and no overload can: it is here because a form holds its values that way.
    ///
    /// - Parameter source: the digits as a `String`, which this cannot unmake.
    /// - Returns: the value holding the digits.
    static func ofString(_ source: String) -> SensitiveDigits {
        SensitiveDigits(Array(source.utf8))
    }

    /// How many characters were supplied. Reads 0 after `close()`.
    var length: Int {
        wiped ? 0 : digits.count
    }

    /// Overwrites the digits for every holder of this value, since one object backs every copy. Idempotent.
    ///
    /// A closed value reads as empty, so a request built from one fails validation as a missing field.
    func close() {
        guard !wiped else { return }
        MemoryWipe.overwrite(&digits)
        wiped = true
    }

    /// The length only. The digits are what this type exists to keep out of a message.
    var description: String {
        "SensitiveDigits(length=\(length))"
    }

    /// The same redacted text on the debug route, which `String(reflecting:)` and a debugger's `po`
    /// render. A debugger's variables view reads memory directly, which no protocol redacts.
    var debugDescription: String {
        description
    }

    /// The length only, for `dump()` and anything else that walks a `Mirror`.
    var customMirror: Mirror {
        Mirror(self, children: ["length": length], displayStyle: .class)
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
        defer { MemoryWipe.overwrite(&filtered) }
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
