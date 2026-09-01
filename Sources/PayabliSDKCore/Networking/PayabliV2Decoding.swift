import Foundation

/// Decodes a v2 envelope from a raw response.
///
/// The base transport's own overload maps a 401 to a typed error, so the recovery layer decodes
/// through this after its own `perform`.
func decodePayabliV2Envelope<T: Decodable & Sendable>(
    _ type: T.Type,
    from response: PayabliResponse
) throws -> PayabliV2Envelope<T> {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
        return try decoder.decode(PayabliV2Envelope<T>.self, from: response.body)
    } catch {
        throw PayabliGenericError(
            code: .decodingError,
            reason: "Failed to decode v2 envelope",
            underlying: error
        )
    }
}
