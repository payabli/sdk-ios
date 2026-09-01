import Foundation

/// Builds the chain applied to every outbound request.
enum RequestDecorationFactory {
    /// Steps that contribute a header or a body field come first. A step that signs over what they
    /// emit goes last.
    static func chain(
        readToken: @escaping @Sendable () async throws -> String
    ) -> [any PayabliRequestDecoration] {
        [
            BearerDecoration(readToken: readToken),
            JSONBodyDecoration()
        ]
    }
}
