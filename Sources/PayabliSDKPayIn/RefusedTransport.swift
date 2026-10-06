import PayabliSDKCore

/// A transport that sends nothing and fails every request with one error.
struct RefusedTransport: PayabliTransport {
    let refusal: PayabliGenericError

    func perform(_: PayabliRequest) async throws -> PayabliResponse {
        throw refusal
    }

    func performV2<T: Decodable & Sendable>(
        _: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw refusal
    }
}
