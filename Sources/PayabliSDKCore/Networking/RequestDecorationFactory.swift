import Foundation

/// Builds the chain applied to every outbound request.
enum RequestDecorationFactory {
    /// Steps that contribute a header or a body field come first. A step that signs over what they
    /// emit goes last.
    ///
    /// - Parameter readToken: reads the bearer the chain attaches, once per request.
    /// - Parameter client: the facts the client header carries.
    /// - Returns: the chain, header steps first and any signing step last.
    static func chain(
        readToken: @escaping @Sendable () async throws -> String,
        client: ClientFacts
    ) -> [any PayabliRequestDecoration] {
        [
            ClientHeaderDecoration(facts: client),
            BearerDecoration(readToken: readToken),
            JSONBodyDecoration()
        ]
    }
}
