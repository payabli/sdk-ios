import Foundation
import PayabliSDKCore

/// Builds a request body as bytes, so a card number never becomes a `String`.
///
/// An encoder would: it produces one immutable value holding the whole body, and nothing can overwrite
/// it afterwards. So everything except `paymentMethod` is encoded normally, that object is written here
/// straight out of its buffers, and the two are joined as bytes.
///
/// **Escaping is delegated, not hand-rolled.** Every ordinary string value is written through a JSON
/// codec's own string escaping, so quotes, backslashes and control characters are its problem. The
/// buffered values need no escaping at all: they are filtered to ASCII digits by the one rule the
/// validators and this writer share, and a digit is never escaped. The routes validate the same buffers
/// before they build a body, so a byte that filter refuses here means the two disagree, and the
/// refusal says so in the same error the validators use.
///
/// Every buffer here that can hold a card number is overwritten before it is dropped: the fragment,
/// the working buffers behind it, and the copy each read takes. The encoded outer body and the quoted
/// field names are dropped without wiping, and hold none of those values.
enum PayInBodyWriter {
    /// The wire spellings of the members the transaction routes write, taken from the coding keys the
    /// capture method already defines, so a member's name is written once.
    private typealias CaptureKeys = PayabliPayInPaymentMethod.CodingKeys

    /// The wire spellings of the members the token-storage route writes, taken from the coding keys the
    /// stored method already defines, so a member's name is written once.
    private typealias StoreKeys = PayabliPayInMethodInput.CodingKeys

    fileprivate static let openBrace: UInt8 = 0x7B
    fileprivate static let closeBrace: UInt8 = 0x7D
    fileprivate static let comma: UInt8 = 0x2C
    fileprivate static let colon: UInt8 = 0x3A
    fileprivate static let quotationMark: UInt8 = 0x22

    /// The `paymentMethod` object for a transaction, whose members are written in the order the
    /// transaction body's writer writes every other object: sorted.
    ///
    /// - Parameter method: the method the transaction charges.
    /// - Returns: the object as bytes, overwritten by ``splice(outer:fragment:)`` once copied.
    static func captureFragment(_ method: PayabliPayInPaymentMethod) throws -> PayInMethodFragment {
        try fragment(quoting: PayInPaymentFlowJSONBody.quoted) { writer in
            switch method {
            case let .card(method):
                try writer.string(CaptureKeys.cardHolder.stringValue, method.data.holderName.payabliCaptureTrimmed)
                try writer.digits(CaptureKeys.cardcvv.stringValue, field: "CVV", method.data.securityCode)
                try writer.string(CaptureKeys.cardexp.stringValue, method.data.normalizedCaptureExpiration())
                try writer.digits(
                    CaptureKeys.cardnumber.stringValue, field: "Card number", method.data.cardNumber
                )
                try writer.string(CaptureKeys.cardzip.stringValue, method.data.postalCode.payabliCaptureTrimmed)
                try writer.optionalString(
                    CaptureKeys.initiator.stringValue,
                    method.initiator?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
                )
                try writer.string(CaptureKeys.method.stringValue, "card")
                try writer.optionalBoolean(CaptureKeys.saveIfSuccess.stringValue, method.saveIfSuccess)

            case let .bankAccount(method):
                try writer.digits(
                    CaptureKeys.achAccount.stringValue, field: "Account number", method.data.accountNumber
                )
                try writer.string(CaptureKeys.achAccountType.stringValue, method.data.accountType.rawValue)
                try writer.string(CaptureKeys.achCode.stringValue, (method.data.secCode ?? .web).rawValue)
                try writer.string(CaptureKeys.achHolder.stringValue, method.data.holderName.payabliCaptureTrimmed)
                try writer.optionalString(CaptureKeys.achHolderType.stringValue, method.data.holderType?.rawValue)
                try writer.string(
                    CaptureKeys.achRouting.stringValue, method.data.routingNumber.payabliCaptureDigitsOnly
                )
                try writer.optionalString(
                    CaptureKeys.device.stringValue,
                    method.data.device?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
                )
                try writer.string(CaptureKeys.method.stringValue, "ach")

            case let .stored(method):
                try writer.string(CaptureKeys.initiator.stringValue, "payor")
                try writer.string(CaptureKeys.method.stringValue, method.method.rawValue)
                try writer.string(CaptureKeys.storedMethodId.stringValue, method.storedMethodId.payabliCaptureTrimmed)

            case let .cloudDevice(method):
                try writer.string(CaptureKeys.device.stringValue, method.device.payabliCaptureTrimmed)
                try writer.string(CaptureKeys.method.stringValue, "cloud")
                try writer.optionalBoolean(CaptureKeys.saveIfSuccess.stringValue, method.saveIfSuccess)

            case let .check(method):
                try writer.string(CaptureKeys.achHolder.stringValue, method.holderName.payabliCaptureTrimmed)
                try writer.string(CaptureKeys.method.stringValue, "check")

            case .cash:
                try writer.string(CaptureKeys.method.stringValue, "cash")
            }
        }
    }

    /// The `paymentMethod` object for a stored method being created, whose members are written in the
    /// order the token-storage route has always sent them.
    ///
    /// - Parameter input: the method the route stores.
    /// - Returns: the object as bytes, overwritten by ``splice(outer:fragment:)`` once copied.
    static func storeFragment(_ input: PayabliPayInMethodInput) throws -> PayInMethodFragment {
        try fragment(quoting: encoderQuoted) { writer in
            switch input {
            case let .card(data):
                try writer.string(StoreKeys.method.stringValue, PayabliPayInMethodType.card.rawValue)
                try writer.string(StoreKeys.cardexp.stringValue, data.normalizedExpiration())
                try writer.string(StoreKeys.cardHolder.stringValue, data.holderName.trimmed)
                try writer.digits(StoreKeys.cardnumber.stringValue, field: "Card number", data.cardNumber)
                try writer.digits(StoreKeys.cardcvv.stringValue, field: "CVV", data.securityCode)
                try writer.string(StoreKeys.cardzip.stringValue, data.postalCode.trimmed)

            case let .bankAccount(data):
                try writer.string(StoreKeys.method.stringValue, PayabliPayInMethodType.bankAccount.rawValue)
                try writer.digits(StoreKeys.achAccount.stringValue, field: "Account number", data.accountNumber)
                try writer.string(StoreKeys.achAccountType.stringValue, data.accountType.rawValue)
                try writer.string(StoreKeys.achHolder.stringValue, data.holderName.trimmed)
                try writer.string(StoreKeys.achRouting.stringValue, data.routingNumber.digitsOnly)
                try writer.string(StoreKeys.achCode.stringValue, (data.secCode ?? .web).rawValue)
                try writer.optionalString(StoreKeys.achHolderType.stringValue, data.holderType?.rawValue)
                try writer.optionalString(StoreKeys.device.stringValue, data.device.map(\.trimmed)?.nilIfEmpty)
            }
        }
    }

    /// Splices `paymentMethod` into an already-encoded body, as the body's last member.
    ///
    /// `outer` holds no buffered value, so it arrives encoded. The fragment does, so it arrives as
    /// bytes and is overwritten here once copied.
    ///
    /// - Parameter outer: the encoded outer body, holding no sensitive value.
    /// - Parameter fragment: the `paymentMethod` member, overwritten here once copied.
    /// - Returns: the body with `paymentMethod` spliced in.
    /// - Throws: ``PayabliGenericError`` when the encoded outer body is not a JSON object.
    static func splice(outer: Data, fragment: PayInMethodFragment) throws -> Data {
        var buffer = ByteBuffer()
        defer {
            // Every exit, not just the one that returns: the refusal below runs while the fragment
            // already holds a card number, and the working buffer holds a copy of it by then.
            fragment.wipe()
            buffer.wipe()
        }
        let outerBytes = [UInt8](outer)
        guard outerBytes.count >= 2, outerBytes.last == closeBrace else {
            throw PayabliGenericError(type: .decodingError, reason: "The encoded body is not a JSON object.")
        }
        // Everything but the closing brace, then the new member, then the brace back.
        buffer.write(outerBytes.dropLast())
        // An empty object takes no separator. The bodies here always carry an entry point, so this is a
        // guard rather than a live case.
        if outerBytes.count > 2 {
            buffer.write(comma)
        }
        buffer.write(try encoderQuoted("paymentMethod").utf8)
        buffer.write(colon)
        buffer.write(fragment.bytes)
        buffer.write(closeBrace)
        return Data(buffer.finishAndWipe())
    }

    /// Overwrites a body the routes built, once the transport has returned.
    ///
    /// After `perform` returns, on both exits: the transport's credential recovery may replay the
    /// request inside the call, and needs the bytes intact to do it. A `Data` copy a caller kept forks
    /// its own storage on this overwrite rather than holding the wiped one, so a reader that retains
    /// the request keeps what it read — the transports are not that, and the tests' recording mock is.
    ///
    /// - Parameter body: the body to overwrite.
    static func wipe(_ body: inout Data) {
        body.withUnsafeMutableBytes { storage in
            guard let base = storage.baseAddress else { return }
            memset(base, 0, storage.count)
        }
    }

    /// Builds one fragment, wiping the writer's working buffer on every exit.
    private static func fragment(
        quoting: @escaping (String) throws -> String,
        build: (FragmentWriter) throws -> Void
    ) throws -> PayInMethodFragment {
        let writer = FragmentWriter(quoting: quoting)
        // After the return as a no-op — `finish()` already wiped the buffer — and on a throw, before
        // the bytes ever leave the writer.
        defer { writer.wipe() }
        try build(writer)
        return PayInMethodFragment(writer.finish())
    }

    /// The quoting the token-storage route's own encoder performs, kept for the members that route
    /// sends as strings, so what the writer writes matches what the route has always sent.
    private static func encoderQuoted(_ value: String) throws -> String {
        guard let quoted = String(data: try JSONEncoder().encode(value), encoding: .utf8) else {
            throw PayabliGenericError(type: .decodingError, reason: "Failed to quote a stored-method string.")
        }
        return quoted
    }
}

/// The `paymentMethod` member as bytes, held so it can be overwritten.
///
/// One object backs the value however many copies of it are carrying it, so the splice overwrites it
/// for every holder at once: a value type would hand each holder a copy to wipe separately.
final class PayInMethodFragment {
    fileprivate var bytes: [UInt8]

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Overwrites the bytes. Idempotent, so wiping a fragment already spliced costs nothing.
    func wipe() {
        for index in bytes.indices {
            bytes[index] = 0
        }
        bytes = []
    }

    /// The bytes as they stand, wiped or not, so a test can assert the overwrite actually happened.
    func rawCopy() -> [UInt8] {
        bytes
    }
}

/// Writes one `paymentMethod` object, member by member.
///
/// String values go through the quoting closure, so escaping is the codec's problem. Digits are
/// written raw between quotes, after the one shared filter, because a digit is never escaped.
private final class FragmentWriter {
    private let quote: (String) throws -> String
    private var buffer = ByteBuffer()
    private var wroteAMember = false

    init(quoting: @escaping (String) throws -> String) {
        quote = quoting
        buffer.write(PayInBodyWriter.openBrace)
    }

    /// Writes `"name":`, with the member separator first except on the first member.
    private func key(_ name: String) throws {
        if wroteAMember {
            buffer.write(PayInBodyWriter.comma)
        }
        wroteAMember = true
        buffer.write(try quote(name).utf8)
        buffer.write(PayInBodyWriter.colon)
    }

    /// A member whose value is an ordinary string, escaped by the quoting closure.
    func string(_ name: String, _ value: String) throws {
        try key(name)
        buffer.write(try quote(value).utf8)
    }

    /// A member written only when the value is present.
    func optionalString(_ name: String, _ value: String?) throws {
        guard let value else { return }
        try string(name, value)
    }

    /// A member whose value is a boolean, written unquoted.
    func optionalBoolean(_ name: String, _ value: Bool?) throws {
        guard let value else { return }
        try key(name)
        buffer.write(value ? "true".utf8 : "false".utf8)
    }

    /// A member whose value is buffered digits: filtered to the ASCII digits a request can write by
    /// the one rule the validators and this writer share, then written raw between quotes.
    func digits(_ name: String, field: String, _ value: SensitiveDigits) throws {
        try key(name)
        buffer.write(PayInBodyWriter.quotationMark)
        try value.useDigitBytes(field: field) { digits in
            buffer.write(digits)
        }
        buffer.write(PayInBodyWriter.quotationMark)
    }

    /// Closes the object.
    ///
    /// - Returns: what was written, the working buffer left holding zeros.
    func finish() -> [UInt8] {
        buffer.write(PayInBodyWriter.closeBrace)
        return buffer.finishAndWipe()
    }

    /// Overwrites what has been written so far. Idempotent, so wiping a writer that already finished
    /// costs nothing.
    func wipe() {
        buffer.wipe()
    }
}

/// A growable byte buffer whose working storage can be overwritten.
///
/// `Data` cannot be, reliably: copy-on-write makes an in-place overwrite fork the storage instead of
/// reaching every copy, so a body assembled through one could leave a card number in a buffer nothing
/// can reach. This owns one array it zeroes on demand.
private struct ByteBuffer {
    private static let initialCapacity = 256

    private var bytes: [UInt8]
    private var size = 0

    init() {
        bytes = Array(repeating: 0, count: Self.initialCapacity)
    }

    mutating func write(_ byte: UInt8) {
        ensure(extra: 1)
        bytes[size] = byte
        size += 1
    }

    mutating func write(_ source: some Sequence<UInt8>) {
        let incoming = Array(source)
        ensure(extra: incoming.count)
        bytes.replaceSubrange(size ..< size + incoming.count, with: incoming)
        size += incoming.count
    }

    /// The exact-size result, after which the working storage holds zeros.
    ///
    /// - Returns: what was written, the working storage left holding zeros.
    mutating func finishAndWipe() -> [UInt8] {
        let result = Array(bytes[0 ..< size])
        wipe()
        return result
    }

    /// Overwrites what has been written so far, for an exit that produces no result.
    mutating func wipe() {
        for index in bytes.indices {
            bytes[index] = 0
        }
        size = 0
    }

    /// The storage being replaced is what would otherwise keep a copy of everything written so far.
    private mutating func ensure(extra: Int) {
        guard size + extra > bytes.count else { return }
        var capacity = bytes.count
        while capacity < size + extra {
            capacity *= 2
        }
        var grown: [UInt8] = Array(repeating: 0, count: capacity)
        grown.replaceSubrange(0 ..< size, with: bytes[0 ..< size])
        for index in bytes.indices {
            bytes[index] = 0
        }
        bytes = grown
    }
}
