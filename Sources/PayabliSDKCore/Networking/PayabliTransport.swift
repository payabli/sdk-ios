import Foundation

/// Transport-level seam used by every endpoint client. Decorators
/// (e.g. authenticated bearer-header injection, request signing) wrap
/// a base implementation without endpoint clients having to know.
package protocol PayabliTransport: Sendable {
    func perform(_ request: PayabliRequest) async throws -> PayabliResponse
    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T>
}
