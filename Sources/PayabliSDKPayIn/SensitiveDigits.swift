import Foundation

/// A card number, security code or bank account number, held so it can be overwritten.
///
/// A `String` cannot be erased: it is immutable, the runtime may move it, and nothing can say when the
/// last copy is gone. This holds the digits as bytes instead, and `close()` overwrites them.
///
/// Whoever supplies the digits decides what they were held in before this, and a text field holds its
/// value as a `String`: this cannot unmake that, and only takes over from here.
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

    /// The same redacted text on the debug route, which is what a debugger and `String(reflecting:)`
    /// render.
    public var debugDescription: String {
        description
    }

    /// The digits, for a rule that reads them. Returns a copy, which the reader is responsible for
    /// overwriting in turn; empty once the value is closed.
    func read() -> [UInt8] {
        wiped ? [] : digits
    }

    /// Runs `body` over the digits, rethrowing whatever `body` throws. The value itself is untouched:
    /// lending the digits is not closing them, so the same value can be lent again afterwards.
    ///
    /// - Parameter body: the rule to run over the digits.
    /// - Returns: what `body` returned.
    func useDigits<T>(_ body: ([UInt8]) throws -> T) rethrows -> T {
        return try body(read())
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
    /// The digits with everything that is not a digit dropped, for the validators and encoders that
    /// read them as text.
    var digitsOnly: String {
        (String(bytes: read(), encoding: .utf8) ?? "").digitsOnly
    }
}
