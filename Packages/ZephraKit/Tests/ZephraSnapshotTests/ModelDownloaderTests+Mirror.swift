import CryptoKit
import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraSnapshot

/// A variant built locally and published on a mirror the stub answers for, and the files the
/// mirror would hold for it. Fetching from the mirror lives in the downloader suite rather
/// than one of its own because `StubHub` is one process-wide stub, and two suites resetting
/// it in parallel answer each other's requests.
enum MirrorFixture {
    static let mirror = ModelMirror(base: URL(string: "https://mirror.test/models")!)
    static let model = ModelDescriptor(
        id: "stub-4bit", displayName: "Stub", variantName: "4-bit", backend: .zImage,
        source: .huggingFace(repoID: "org/repo", revision: "main", filePatterns: ["*"]),
        quantization: .int4, downloadBytes: 100, residentBytes: 10, peakBytes: 20, tiledPeakBytes: 15,
        maxPromptTokens: 8, capabilities: ModelCatalog.zImageTurbo4bit.capabilities, builtBytes: 30,
        mirror: mirror)

    /// The variant's files as the mirror would hold them, keyed by their whole path.
    static let files: [String: Data] = [
        "quantization.json": Data("{}".utf8),
        "transformer/model.safetensors": Data(repeating: 3, count: 24),
        ".zephra-packed-source": try! JSONEncoder().encode(PackedProvenance.identity(model)),
    ]

    /// An index naming `model` with `files`, packed as `identity` says, digests computed from
    /// the bytes except for the one file `corrupting` names.
    static func index(identity: [String] = PackedProvenance.identity(model), corrupting: String? = nil)
        -> Data
    {
        let entries = files.map { path, data -> [String: Any] in
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return ["path": path, "bytes": data.count, "sha256": path == corrupting ? String(repeating: "0", count: 64) : digest]
        }
        let index: [String: Any] = ["models": [model.id: ["bytes": 30, "source": identity, "files": entries]]]
        return try! JSONSerialization.data(withJSONObject: index)
    }

    /// The files as the stub serves them, under the mirror's directory for the variant.
    static func served() -> [String: Data] {
        Dictionary(uniqueKeysWithValues: files.map { ("models/\(model.id)/\($0.key)", $0.value) })
    }
}

extension ModelDownloaderTests {
    private typealias Fixture = MirrorFixture

    @Test("the variant lands in the built directory whole, stamped, with no partial left behind")
    func variantLandsInTheBuiltDirectory() async throws {
        let scratch = Scratch("Mirror")
        let locations = ModelLocations(root: scratch.url("models"))
        StubHub.reset(StubHub.Behaviour(files: Fixture.served(), index: Fixture.index()))

        let progress = ProgressLog()
        let fetched = try await downloader().fetchPrebuilt(Fixture.model, into: locations) { progress.record($0) }

        #expect(fetched == locations.built(Fixture.model))
        #expect(scratch.hasFile("models/stub-4bit/quantization.json"))
        #expect(scratch.hasFile("models/stub-4bit/transformer/model.safetensors"))
        #expect(!FileManager.default.fileExists(atPath: scratch.url("models/stub-4bit.partial").path))
        #expect(PackedProvenance.matches(Fixture.model, in: locations.built(Fixture.model)))
        #expect(LocalSnapshot(requiredEntries: ["quantization.json"]).packedVariant(of: Fixture.model, in: locations) != nil)
        #expect(progress.last?.fraction == 1)
        #expect(StubHub.records.allSatisfy { $0.authorization == nil })
        #expect(!StubHub.records.contains { $0.path.contains("/api/models/") })
    }

    @Test("a mirror with no index, or none naming the variant, answers nil and writes nothing")
    func absentVariantIsNil() async throws {
        let scratch = Scratch("Mirror")
        let locations = ModelLocations(root: scratch.url("models"))
        StubHub.reset(StubHub.Behaviour(files: Fixture.served(), index: nil))
        #expect(try await downloader().fetchPrebuilt(Fixture.model, into: locations) { _ in } == nil)

        let other: [String: Any] = ["models": ["someone-else": ["bytes": 1, "source": [], "files": []]]]
        StubHub.reset(StubHub.Behaviour(files: Fixture.served(), index: try JSONSerialization.data(withJSONObject: other)))
        #expect(try await downloader().fetchPrebuilt(Fixture.model, into: locations) { _ in } == nil)
        #expect(!FileManager.default.fileExists(atPath: scratch.url("models/stub-4bit.partial").path))
        #expect(!FileManager.default.fileExists(atPath: scratch.url("models/stub-4bit").path))
    }

    @Test("a variant the index says was packed from something else is not this variant")
    func identityMismatchIsNil() async throws {
        let scratch = Scratch("Mirror")
        let locations = ModelLocations(root: scratch.url("models"))
        StubHub.reset(StubHub.Behaviour(files: Fixture.served(), index: Fixture.index(identity: ["stub-4bit", "org/other"])))
        #expect(try await downloader().fetchPrebuilt(Fixture.model, into: locations) { _ in } == nil)
        #expect(!StubHub.records.contains { $0.path.hasSuffix("quantization.json") })
    }

    @Test("a file whose digest is not the index's is discarded rather than kept")
    func checksumMismatchDiscardsTheFile() async throws {
        let scratch = Scratch("Mirror")
        let locations = ModelLocations(root: scratch.url("models"))
        StubHub.reset(StubHub.Behaviour(files: Fixture.served(), index: Fixture.index(corrupting: "transformer/model.safetensors")))
        let part = try #require(RepositoryDownload.prebuilt(Fixture.model, in: locations))

        await #expect(throws: ModelDownloadError.checksumMismatch(path: "transformer/model.safetensors")) {
            try await downloader().download([part]) { _ in }
        }
        #expect(!scratch.hasFile("models/stub-4bit.partial/transformer/model.safetensors"))
        #expect(!scratch.hasFile("models/stub-4bit.partial/transformer/model.safetensors.incomplete"))
        #expect(!FileManager.default.fileExists(atPath: scratch.url("models/stub-4bit").path))
    }

    @Test("a mirror that answers with an error is nil at once, with no retries and nothing on disk")
    func unreachableMirrorIsNilWithoutRetrying() async throws {
        let scratch = Scratch("Mirror")
        let locations = ModelLocations(root: scratch.url("models"))
        // The stub forces the status on listing requests; the index is one, and 503 is what a
        // host that is down looks like from here.
        var behaviour = StubHub.Behaviour(files: Fixture.served(), index: Fixture.index())
        behaviour.listingStatus = 503
        StubHub.reset(behaviour)
        let started = ContinuousClock.now
        #expect(try await downloader().fetchPrebuilt(Fixture.model, into: locations) { _ in } == nil)
        #expect(ContinuousClock.now - started < .seconds(1))
        #expect(StubHub.records.count == 1)
        #expect(!FileManager.default.fileExists(atPath: scratch.url("models/stub-4bit.partial").path))

        let pool = ModelTransfers(downloader: downloader())
        let id = UUID()
        try await pool.reserve(id, model: Fixture.model, locations: locations)
        let fetched = try await TransferAcquisition(id: id, pool: pool)
            .fetchPrebuilt(Fixture.model, into: locations) { _ in }
        try await pool.release(id)
        #expect(fetched == nil)
    }

    @Test("a model without a mirror answers nil without a request")
    func unpublishedModelIsNil() async throws {
        let scratch = Scratch("Mirror")
        StubHub.reset(StubHub.Behaviour())
        let fetched = try await downloader().fetchPrebuilt(
            ModelCatalog.zImageTurbo8bit, into: ModelLocations(root: scratch.url("models"))) { _ in }
        #expect(fetched == nil)
        #expect(StubHub.records.isEmpty)
    }

    @Test("through the transfer pool the variant is claimed, fetched once and published")
    func poolFetchesAndPublishes() async throws {
        let scratch = Scratch("Mirror")
        let locations = ModelLocations(root: scratch.url("models"))
        StubHub.reset(StubHub.Behaviour(files: Fixture.served(), index: Fixture.index()))
        let pool = ModelTransfers(downloader: downloader())
        let id = UUID()
        try await pool.reserve(id, model: Fixture.model, locations: locations)
        let fetched = try await TransferAcquisition(id: id, pool: pool)
            .fetchPrebuilt(Fixture.model, into: locations) { _ in }
        try await pool.release(id)

        #expect(fetched == locations.built(Fixture.model))
        #expect(PackedProvenance.matches(Fixture.model, in: locations.built(Fixture.model)))
        #expect(StubHub.records.filter { $0.path.hasSuffix("/index.json") }.count == 1)
    }
}
