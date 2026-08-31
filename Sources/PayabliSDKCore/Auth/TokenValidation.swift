import Foundation

private let firstPrintableASCII: UInt32 = 0x20
private let lastPrintableASCII: UInt32 = 0x7E

extension String {
    /// True when every character can legally sit in an HTTP header value.
    ///
    /// A token reaches the wire as `Authorization: Bearer <token>`. A carriage return
    /// or line feed in it is header injection, and `URLRequest.setValue` drops or
    /// mangles such a header rather than reporting it, so the request goes out
    /// unauthenticated and the caller sees a 401 for the wrong reason.
    ///
    /// Printable US-ASCII only, which is what a bearer credential is made of. An
    /// empty string satisfies this, so blank is checked on its own.
    var isHeaderSafe: Bool {
        unicodeScalars.allSatisfy { $0.value >= firstPrintableASCII && $0.value <= lastPrintableASCII }
    }
}
