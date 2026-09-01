import Foundation

/// Labels a request that carries a body and names no content type of its own.
///
/// A content type already on the request is left in place, whatever case it is spelled in.
struct JSONBodyDecoration: PayabliRequestDecoration {
    func decorate(_ request: PayabliRequest) async throws -> PayabliRequest {
        guard request.body != nil, !request.namesHeader(PayabliRequest.contentTypeHeader) else {
            return request
        }
        return request.withHeaders(
            [PayabliRequest.contentTypeHeader: PayabliRequest.applicationJSON]
        )
    }
}
