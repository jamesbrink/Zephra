import Foundation
import Synchronization

/// A Hugging Face that is not there: a `URLProtocol` standing in for the hub, so the downloader
/// can be driven through resuming, truncation, refusal and cancellation with no network.
///
/// It answers the two endpoints the downloader knows. `/api/models/<repo>/tree/<revision>`
/// returns one page of `pages`, with a `Link: rel="next"` header while there are more, and
/// `/<repo>/resolve/<revision>/<path>` returns the bytes in `files`, honouring `Range` unless
/// it is told to ignore it. Every request is recorded, which is how "no `Authorization` header,
/// ever" is asserted rather than assumed.
final class StubHub: URLProtocol, @unchecked Sendable {
    /// What the stub does with the requests it gets.
    struct Behaviour: Sendable {
        /// The listing pages, in order; the stub links each to the next.
        var pages: [Data] = []
        /// The repository's files, by path.
        var files: [String: Data] = [:]
        /// Answer a `Range` request with the whole file and a 200, the way a server that does
        /// not do ranges would.
        var ignoresRange = false
        /// Send only this many bytes of the body and then finish, the way a connection that
        /// dropped mid-file would.
        var truncatesTo: Int?
        /// Force this status on every file request.
        var fileStatus: Int?
        /// Force this status on every listing request.
        var listingStatus: Int?
        /// Take this long before answering, so a test can stop a transfer that is in flight.
        var pause: TimeInterval = 0
        /// The `ETag` every file answer carries; a resume whose `If-Range` names another is
        /// answered with the whole file, the way a file that changed would be.
        var etag: String?
    }

    /// One request as the stub saw it.
    struct Record: Sendable {
        var path: String
        var range: String?
        var authorization: String?
        var ifRange: String?
    }

    private struct State: Sendable {
        var behaviour = Behaviour()
        var records: [Record] = []
    }

    private static let state = Mutex(State())
    private let stopped = Mutex(false)

    /// Starts a fresh hub answering as `behaviour` says.
    static func reset(_ behaviour: Behaviour) {
        state.withLock { $0 = State(behaviour: behaviour) }
    }

    /// Every request the stub has been given since the last reset.
    static var records: [Record] { state.withLock { $0.records } }

    /// A session configuration that reaches this stub and nothing else.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubHub.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func stopLoading() {
        stopped.withLock { $0 = true }
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let behaviour = Self.state.withLock { state -> Behaviour in
            state.records.append(
                Record(
                    path: url.path(percentEncoded: false),
                    range: request.value(forHTTPHeaderField: "Range"),
                    authorization: request.value(forHTTPHeaderField: "Authorization"),
                    ifRange: request.value(forHTTPHeaderField: "If-Range")))
            return state.behaviour
        }
        if url.path(percentEncoded: false).contains("/api/models/") {
            serveListing(url, behaviour)
        } else {
            serveFile(url, behaviour)
        }
    }

    private func serveListing(_ url: URL, _ behaviour: Behaviour) {
        if let status = behaviour.listingStatus, status != 200 {
            return finish(url, status: status, headers: [:], body: Data())
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let page = components?.queryItems?.first { $0.name == "page" }?.value.flatMap(Int.init) ?? 1
        guard page >= 1, page <= behaviour.pages.count else {
            return finish(url, status: 404, headers: [:], body: Data())
        }
        var headers: [String: String] = ["Content-Type": "application/json"]
        if page < behaviour.pages.count, var next = components {
            next.queryItems = (next.queryItems ?? []).filter { $0.name != "page" }
                + [URLQueryItem(name: "page", value: String(page + 1))]
            if let link = next.url {
                headers["Link"] = "<\(link.absoluteString)>; rel=\"next\""
            }
        }
        finish(url, status: 200, headers: headers, body: behaviour.pages[page - 1])
    }

    private func serveFile(_ url: URL, _ behaviour: Behaviour) {
        if let status = behaviour.fileStatus, status != 200 {
            return finish(url, status: status, headers: [:], body: Data())
        }
        // `/<org>/<repo>/resolve/<revision>/<path>`: everything after the revision is the file.
        let path = url.path(percentEncoded: false)
        guard let marker = path.range(of: "/resolve/") else {
            return finish(url, status: 404, headers: [:], body: Data())
        }
        let name = path[marker.upperBound...].split(separator: "/").dropFirst()
            .joined(separator: "/")
        guard let body = behaviour.files[name] else {
            return finish(url, status: 404, headers: [:], body: Data())
        }
        let requested = request.value(forHTTPHeaderField: "Range")
        let offset = requested.flatMap(Self.offset(of:)) ?? 0
        let ifRange = request.value(forHTTPHeaderField: "If-Range")
        let unchanged = ifRange == nil || ifRange == behaviour.etag
        var tag: [String: String] = [:]
        if let etag = behaviour.etag { tag["ETag"] = etag }
        if requested != nil, !behaviour.ignoresRange, unchanged, offset > 0, offset < body.count {
            let rest = body.suffix(from: offset)
            finish(
                url, status: 206,
                headers: tag.merging([
                    "Content-Length": String(rest.count),
                    "Content-Range": "bytes \(offset)-\(body.count - 1)/\(body.count)",
                ]) { $1 },
                body: Data(rest), behaviour: behaviour)
        } else {
            finish(
                url, status: 200, headers: tag.merging(["Content-Length": String(body.count)]) { $1 },
                body: body, behaviour: behaviour)
        }
    }

    /// The first byte a `bytes=N-` header asks for.
    private static func offset(of header: String) -> Int? {
        guard header.hasPrefix("bytes=") else { return nil }
        return Int(header.dropFirst("bytes=".count).prefix { $0.isNumber })
    }

    /// Answers, after dawdling for `pause` when the behaviour asks it to.
    ///
    /// Nothing handed to the client reaches the session until `startLoading` returns — the
    /// session flushes the protocol's callbacks in one go — so a transfer cannot be made to
    /// dribble in. What it can be made to do is take its time before answering at all, which
    /// is what a test that cancels mid-transfer needs. The waiting runs the loading thread's
    /// run loop rather than sleeping on it, so the session's cancellation reaches `stopLoading`.
    private func finish(
        _ url: URL, status: Int, headers: [String: String], body: Data,
        behaviour: Behaviour = Behaviour()
    ) {
        if behaviour.pause > 0 {
            let deadline = Date().addingTimeInterval(behaviour.pause)
            while Date() < deadline {
                if stopped.withLock({ $0 }) { return }
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
        }
        guard !stopped.withLock({ $0 }),
              let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let sent = behaviour.truncatesTo.map { Data(body.prefix($0)) } ?? body
        if !sent.isEmpty { client?.urlProtocol(self, didLoad: sent) }
        client?.urlProtocolDidFinishLoading(self)
    }
}
