import Foundation

/// Builds the chain applied to every outbound request.
enum RequestDecorationFactory {
    /// Steps that contribute a header or a body field come first. A step that signs over what they
    /// emit goes last.
    ///
    /// - Parameter readToken: reads the bearer the chain attaches, once per request.
    /// - Parameter readHeldToken: reads the bearer already held, without minting, for a request that requires one.
    /// - Parameter client: the facts the client header carries.
    /// - Returns: the chain, header steps first and any signing step last.
    static func chain(
        readToken: @escaping @Sendable () async throws -> String,
        readHeldToken: @escaping @Sendable () async -> String?,
        client: ClientFacts
    ) -> [any PayabliRequestDecoration] {
        [
            ClientHeaderDecoration(facts: client),
            BearerDecoration(readToken: readToken, readHeldToken: readHeldToken),
            JSONBodyDecoration()
        ]
    }
}
