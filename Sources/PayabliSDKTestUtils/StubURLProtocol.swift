import Foundation

/// A URLProtocol that returns programmed responses instead of hitting the network.
///
/// Usage:
/// ```swift
/// let session = StubURLProtocol.makeSession()
/// StubURLProtocol.handler = { request in
///     (HTTPURLResponse(...), Data(...))
/// }
/// defer { StubURLProtocol.handler = nil }
/// ```
///
/// POST bodies streamed via `httpBodyStream` are drained into `httpBody`
/// automatically, so test handlers can inspect the request payload.
package final class StubURLProtocol: URLProtocol {
    package typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    package nonisolated(unsafe) static var handler: Handler?

    override public class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override public func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        // URLSession streams POST bodies via httpBodyStream. Drain it into
        // httpBody so test handlers can inspect the payload.
        var inspectable = request
        if inspectable.httpBody == nil, let stream = inspectable.httpBodyStream {
            inspectable.httpBody = Self.drain(stream)
        }

        do {
            let (response, data) = try handler(inspectable)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override public func stopLoading() {}

    /// Returns a `URLSession` pre-configured to intercept all requests with
    /// this protocol. Register a `handler` before making requests.
    package static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
