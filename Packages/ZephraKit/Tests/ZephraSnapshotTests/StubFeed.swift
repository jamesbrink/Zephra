import Foundation
import Synchronization

/// An update server that is not there: a `URLProtocol` standing in for the assets bucket, so
/// the feed and the disk-image download can be driven through a refusal, junk and a transport
/// failure with no network.
///
/// A stub of its own rather than `StubHub`'s, and keyed by host rather than process-wide.
/// `StubHub` keeps one behaviour for the whole process, which is why every suite that uses it
/// lives inside one `.serialized` suite; Swift Testing runs *different* suites in parallel, so
/// a second suite resetting a shared stub would answer a model download's requests with a
/// release manifest. Each suite here takes a host of its own and they cannot collide.
final class StubFeed: URLProtocol, @unchecked Sendable {
    /// What the stub does with the requests it gets for one host.
    struct Behaviour: Sendable {
        /// Bodies by request path, the way the bucket holds keys.
        var bodies: [String: Data] = [:]
        /// Force this status on every request; 200 serves `bodies`.
        var status = 200
        /// Fail the request the way a connection that never got an answer would, instead of
        /// answering at all.
        var failsWith: URLError.Code?
    }

    private static let hosts = Mutex<[String: Behaviour]>([:])

    /// Starts a fresh server for `host`, answering as `behaviour` says.
    static func reset(host: String, _ behaviour: Behaviour) {
        hosts.withLock { $0[host] = behaviour }
    }

    /// A session configuration that reaches this stub and nothing else.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubFeed.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let behaviour = Self.hosts.withLock { $0[url.host() ?? ""] } ?? Behaviour()
        if let code = behaviour.failsWith {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        let path = url.path(percentEncoded: false)
        guard behaviour.status == 200, let body = behaviour.bodies[path] else {
            return finish(url, status: behaviour.status == 200 ? 404 : behaviour.status, body: Data())
        }
        finish(url, status: 200, body: body)
    }

    private func finish(_ url: URL, status: Int, body: Data) {
        guard let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(body.count)])
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }
}
