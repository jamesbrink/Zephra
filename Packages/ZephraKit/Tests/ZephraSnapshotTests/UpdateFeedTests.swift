import Foundation
import Testing

@testable import ZephraSnapshot

@Suite("Reading what the newest published Zephra is", .serialized)
struct UpdateFeedTests {
    /// This suite's own host, so `StubFeed` answers it and nothing else; see `StubFeed`.
    private static let host = "feed.test"
    private static let url = URL(string: "https://\(host)/releases/latest.json")!

    private func feed() -> UpdateFeed {
        UpdateFeed(url: Self.url, configuration: StubFeed.configuration())
    }

    private static let manifest = Data(
        """
        {"url":"https://feed.test/releases/Zephra-0.1.0-202609120231.dmg",\
        "version":"0.1.0","build":"202609120231",\
        "sha256":"0000000000000000000000000000000000000000000000000000000000000000"}
        """.utf8)

    @Test("the manifest the bucket serves is the release the app compares itself with")
    func readsTheManifest() async throws {
        StubFeed.reset(host: Self.host, StubFeed.Behaviour(bodies: ["/releases/latest.json": Self.manifest]))
        let latest = try await feed().latest()
        #expect(latest.build == "202609120231")
        #expect(latest.version == "0.1.0")
    }

    @Test("a status that is not 200 is a refusal that names it")
    func refusalNamesTheStatus() async {
        StubFeed.reset(host: Self.host, StubFeed.Behaviour(status: 404))
        await #expect(throws: UpdateFeedError.refused(status: 404)) { try await feed().latest() }
    }

    @Test("bytes that are not a release manifest are malformed, not a crash")
    func junkIsMalformed() async {
        StubFeed.reset(host: Self.host, StubFeed.Behaviour(bodies: ["/releases/latest.json": Data("<html>nope</html>".utf8)]))
        await #expect(throws: UpdateFeedError.malformed) { try await feed().latest() }
    }

    @Test("a request that never gets an answer is unreachable, with something to read")
    func transportFailureIsUnreachable() async {
        StubFeed.reset(host: Self.host, StubFeed.Behaviour(failsWith: .notConnectedToInternet))
        do {
            _ = try await feed().latest()
            Issue.record("expected the feed to be unreachable")
        } catch let error as UpdateFeedError {
            guard case .unreachable(let reason) = error else {
                Issue.record("expected unreachable, got \(error)")
                return
            }
            #expect(!reason.isEmpty)
            #expect(error.message.contains(reason))
        } catch {
            Issue.record("expected an UpdateFeedError, got \(error)")
        }
    }
}
