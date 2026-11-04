import Foundation
import PayabliSDKCore

/// Builds a request body as bytes, so a card number never becomes a `String`.
///
/// Everything except `paymentMethod` is encoded normally, that object is written here straight out
/// of its buffers, and every buffer that can hold a card number is overwritten before it is dropped.
enum PayInBodyWriter {
    private typealias CaptureKeys = PayabliPayInPaymentMethod.CodingKeys

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
                try writer.string(CaptureKeys.cardexp.stringValue, method.data.wireExpiry)
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
                    method.data.deviceId?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
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

    /// The `paymentMethod` object for a stored method being created, in the token-storage route's order.
    ///
    /// - Parameter input: the method the route stores.
    /// - Returns: the object as bytes, overwritten by ``splice(outer:fragment:)`` once copied.
    static func storeFragment(_ input: PayabliPayInMethodInput) throws -> PayInMethodFragment {
        try fragment(quoting: encoderQuoted) { writer in
            switch input {
            case let .card(data):
                try writer.string(StoreKeys.method.stringValue, PayabliPayInMethodType.card.rawValue)
                try writer.string(StoreKeys.cardexp.stringValue, data.wireExpiry)
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
                try writer.optionalString(StoreKeys.device.stringValue, data.deviceId.map(\.trimmed)?.nilIfEmpty)
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
    /// - Parameter releaseNoted: reads the released bytes, proving the overwrite; routes pass nothing.
    /// - Returns: the body with `paymentMethod` spliced in, owning its allocation.
    /// - Throws: ``PayabliGenericError`` when the encoded outer body is not a JSON object.
    static func splice(
        outer: Data,
        fragment: PayInMethodFragment,
        releaseNoted: (@Sendable (UnsafeRawPointer, Int) -> Void)? = nil
    ) throws -> Data {
        var buffer = ByteBuffer()
        defer {
            fragment.wipe()
            buffer.wipe()
        }
        let outerBytes = [UInt8](outer)
        guard outerBytes.count >= 2, outerBytes.last == closeBrace else {
            throw PayabliGenericError(type: .decodingError, reason: "The encoded body is not a JSON object.")
        }
        buffer.write(outerBytes.dropLast())
        if outerBytes.count > 2 {
            buffer.write(comma)
        }
        buffer.write(try encoderQuoted("paymentMethod").utf8)
        buffer.write(colon)
        buffer.write(fragment.bytes)
        buffer.write(closeBrace)
        var finished = buffer.finishAndWipe()
        let spliced = ownedBody(finished, releaseNoted: releaseNoted)
        MemoryWipe.overwrite(&finished)
        return spliced
    }

    /// A finished body as a `Data` owning its bytes, overwritten by whichever holder frees them.
    ///
    /// `URLRequest.httpBody` keeps the `Data` it is given, so the platform holds this allocation
    /// past the routes' wipe until it drops the request; the release zeroes it, whichever frees it.
    ///
    /// - Parameter finished: the finished body bytes, copied into the allocation this returns.
    /// - Parameter releaseNoted: reads the released bytes, proving the overwrite; routes pass nothing.
    /// - Returns: the body, owning its allocation.
    private static func ownedBody(
        _ finished: [UInt8],
        releaseNoted: (@Sendable (UnsafeRawPointer, Int) -> Void)? = nil
    ) -> Data {
        guard !finished.isEmpty else { return Data() }
        let count = finished.count
        let allocation = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
        finished.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            memcpy(allocation, base, count)
        }
        return Data(bytesNoCopy: allocation, count: count, deallocator: .custom { pointer, count in
            MemoryWipe.overwrite(pointer, count: count)
            if let releaseNoted {
                releaseNoted(UnsafeRawPointer(pointer), count)
            }
            pointer.deallocate()
        })
    }

    /// Overwrites a body the routes built, once the transport has returned: a replay inside the
    /// call needs the bytes intact until then. A `Data` copy a caller kept forks its own storage,
    /// so this reaches the routes' copy; a request's kept allocation is overwritten at its release.
    ///
    /// - Parameter body: the body to overwrite.
    static func wipe(_ body: inout Data) {
        body.withUnsafeMutableBytes { MemoryWipe.overwrite($0) }
    }

    /// Builds one fragment, wiping the writer's working buffer on every exit.
    private static func fragment(
        quoting: @escaping (String) throws -> String,
        build: (FragmentWriter) throws -> Void
    ) throws -> PayInMethodFragment {
        let writer = FragmentWriter(quoting: quoting)
        defer { writer.wipe() }
        try build(writer)
        return PayInMethodFragment(writer.finish())
    }

    /// Quotes a string as the token-storage route's encoder does.
    ///
    /// - Parameter value: the string to quote.
    /// - Returns: the quoted, escaped string.
    private static func encoderQuoted(_ value: String) throws -> String {
        guard let quoted = String(data: try JSONEncoder().encode(value), encoding: .utf8) else {
            throw PayabliGenericError(type: .decodingError, reason: "Failed to quote a stored-method string.")
        }
        return quoted
    }
}

/// The `paymentMethod` member as bytes, held so it can be overwritten. One object backs every copy,
/// so one wipe reaches every holder.
final class PayInMethodFragment: CustomReflectable {
    fileprivate var bytes: [UInt8]

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var customMirror: Mirror {
        Mirror(self, children: ["count": bytes.count], displayStyle: .class)
    }

    /// Overwrites the bytes in place, keeping the zeros. Idempotent, so wiping a fragment already
    /// spliced costs nothing.
    func wipe() {
        MemoryWipe.overwrite(&bytes)
    }

    /// The bytes as they stand, wiped or not, so a test can assert the overwrite actually happened.
    func rawCopy() -> [UInt8] {
        bytes
    }
}

/// Writes one `paymentMethod` object, member by member. Strings go through the quoting closure, and
/// digits are written between quotes after the shared ASCII filter.
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

/// A growable byte buffer whose working storage is overwritten in place, which `Data`'s copy-on-write
/// storage cannot guarantee.
struct ByteBuffer: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
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
        var incoming = Array(source)
        ensure(extra: incoming.count)
        bytes.replaceSubrange(size ..< size + incoming.count, with: incoming)
        size += incoming.count
        MemoryWipe.overwrite(&incoming)
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
        MemoryWipe.overwrite(&bytes)
        size = 0
    }

    /// The whole working storage, written or not, so a test can assert the overwrite actually happened.
    func rawStorage() -> [UInt8] {
        bytes
    }

    var description: String {
        "ByteBuffer(size=\(size))"
    }

    var debugDescription: String {
        description
    }

    var customMirror: Mirror {
        Mirror(self, children: ["size": size], displayStyle: .struct)
    }

    /// Grows the storage to fit `extra` more bytes, overwriting the storage it replaces.
    ///
    /// - Parameter extra: how many more bytes the buffer has to hold.
    private mutating func ensure(extra: Int) {
        guard size + extra > bytes.count else { return }
        var capacity = bytes.count
        while capacity < size + extra {
            capacity *= 2
        }
        var grown: [UInt8] = Array(repeating: 0, count: capacity)
        grown.replaceSubrange(0 ..< size, with: bytes[0 ..< size])
        MemoryWipe.overwrite(&bytes)
        bytes = grown
    }
}
