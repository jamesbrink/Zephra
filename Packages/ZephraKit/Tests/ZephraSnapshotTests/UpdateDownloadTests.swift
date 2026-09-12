import CryptoKit
import Foundation
import Testing
import ZephraTestSupport

@testable import ZephraSnapshot

@Suite("Fetching the disk image a release manifest names", .serialized)
struct UpdateDownloadTests {
    /// This suite's own host, so `StubFeed` answers it and nothing else; see `StubFeed`.
    private static let host = "images.test"
    private static let path = "/releases/Zephra-0.1.0-202609120231.dmg"
    private static let image = Data(repeating: 7, count: 64 << 10)

    private func manifest(sha256: String) -> ReleaseManifest {
        ReleaseManifest(
            url: URL(string: "https://\(Self.host)\(Self.path)")!,
            version: "0.1.0", build: "202609120231", sha256: sha256)
    }

    private static var digest: String {
        SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
    }

    private func download() -> UpdateDownload {
        UpdateDownload(configuration: StubFeed.configuration())
    }

    @Test("the image lands under its build, whole, with nothing part-way left beside it")
    func landsVerified() async throws {
        StubFeed.reset(host: Self.host, StubFeed.Behaviour(bodies: [Self.path: Self.image]))
        let scratch = Scratch("Update")
        let fetched = try await download().fetch(
            manifest(sha256: Self.digest), into: scratch.url("Updates")) { _ in }

        #expect(fetched.lastPathComponent == "Zephra-202609120231.dmg")
        #expect(try Data(contentsOf: fetched) == Self.image)
        let beside = try FileManager.default.contentsOfDirectory(atPath: scratch.url("Updates").path(percentEncoded: false))
        #expect(beside == ["Zephra-202609120231.dmg"])
    }

    @Test("progress is a fraction of the whole and ends at one")
    func progressEndsAtOne() async throws {
        StubFeed.reset(host: Self.host, StubFeed.Behaviour(bodies: [Self.path: Self.image]))
        let scratch = Scratch("Update")
        let seen = FractionLog()
        _ = try await download().fetch(manifest(sha256: Self.digest), into: scratch.url("Updates")) {
            seen.record($0)
        }

        let fractions = seen.fractions
        #expect(fractions.last == 1)
        #expect(fractions.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(fractions == fractions.sorted())
    }

    @Test("an image whose digest is not the published one is discarded and leaves no file")
    func checksumMismatchLeavesNoFile() async throws {
        StubFeed.reset(host: Self.host, StubFeed.Behaviour(bodies: [Self.path: Self.image]))
        let scratch = Scratch("Update")
        let wrong = manifest(sha256: String(repeating: "0", count: 64))

        await #expect(throws: UpdateDownloadError.checksumMismatch) {
            _ = try await download().fetch(wrong, into: scratch.url("Updates")) { _ in }
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: scratch.url("Updates").path(percentEncoded: false))
        #expect(left.isEmpty)
    }

    @Test("a build that is not a stamp never reaches the file system")
    func aNonStampIsRefused() async throws {
        StubFeed.reset(host: Self.host, StubFeed.Behaviour(bodies: [Self.path: Self.image]))
        let scratch = Scratch("Update")
        var odd = manifest(sha256: Self.digest)
        odd.build = "../../etc"

        await #expect(throws: UpdateDownloadError.notARelease) {
            _ = try await download().fetch(odd, into: scratch.url("Updates")) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.url("Updates").path(percentEncoded: false)))
    }

    @Test("a status that is not 200 is a refusal that names it")
    func refusalNamesTheStatus() async throws {
        StubFeed.reset(host: Self.host, StubFeed.Behaviour(status: 403))
        let scratch = Scratch("Update")
        await #expect(throws: UpdateDownloadError.refused(status: 403)) {
            _ = try await download().fetch(manifest(sha256: Self.digest), into: scratch.url("Updates")) { _ in }
        }
    }
}

/// What a download told its caller, for the suites that check the shape of the progress rather
/// than any one figure.
private final class FractionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [Double] = []

    func record(_ fraction: Double) {
        lock.lock()
        defer { lock.unlock() }
        seen.append(fraction)
    }

    var fractions: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }
}
