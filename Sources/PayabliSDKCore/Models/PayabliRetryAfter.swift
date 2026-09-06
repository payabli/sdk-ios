import Foundation

/// An error carrying the server's own instruction on how long to wait before trying again.
///
/// Adopted only by the errors whose status can carry the header, rather than being a property on every
/// error: a value that is `nil` everywhere it appears says nothing about where it can appear at all.
public protocol PayabliRetryAfter {
    /// The wait the server asked for, or `nil` when it sent no usable instruction.
    var retryAfter: TimeInterval? { get }
}
