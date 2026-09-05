import Foundation
import Testing
import ZephraTestSupport

@testable import ZephraQuantization

/// The quantizer empties what it writes to, so a destination that touches the source is
/// refused before a byte of the source is read. The shards here are empty files: a run that
/// got as far as reading one would fail on its header, and a refusal that names the overlap
/// is the proof it never did.
@Suite("Snapshot quantizer")
struct SnapshotQuantizerTests {
    @Test("a destination inside the source is refused before anything is read")
    func refusesADestinationInsideTheSource() throws {
        let scratch = try Self.release()
        Self.expectOverlap {
            try SnapshotQuantizer.quantize(
                source: scratch.url("release"),
                destination: scratch.url("release/packed"),
                plan: try Self.plan())
        }
        #expect(scratch.hasFile("release/transformer/model.safetensors"))
        #expect(!scratch.hasFile("release/packed"), "nothing was created for the refused build")
    }

    @Test("a destination that is the source through a symlink is refused")
    func refusesTheSourceThroughALink() throws {
        let scratch = try Self.release()
        try scratch.link("packed", to: "release")
        Self.expectOverlap {
            try SnapshotQuantizer.quantize(
                source: scratch.url("release"),
                destination: scratch.url("packed"),
                plan: try Self.plan())
        }
        #expect(scratch.hasFile("release/transformer/model.safetensors"))
    }

    @Test("a destination under a link to the source is refused, though it does not exist yet")
    func refusesANewDirectoryUnderALinkToTheSource() throws {
        let scratch = try Self.release()
        try scratch.link("elsewhere", to: "release")
        Self.expectOverlap {
            try SnapshotQuantizer.quantize(
                source: scratch.url("release"),
                destination: scratch.url("elsewhere/packed"),
                plan: try Self.plan())
        }
        #expect(!scratch.hasFile("release/packed"))
    }

    @Test("a source inside the destination is refused")
    func refusesASourceInsideTheDestination() throws {
        let scratch = try Self.release(at: "models/release")
        Self.expectOverlap {
            try SnapshotQuantizer.quantize(
                source: scratch.url("models/release"),
                destination: scratch.url("models"),
                plan: try Self.plan())
        }
        #expect(scratch.hasFile("models/release/transformer/model.safetensors"))
    }

    @Test("the transactional build refuses the overlap before it replaces the destination")
    func theBuildRefusesBeforeReplacingTheDestination() throws {
        let scratch = try Self.release(at: "models/release")
        Self.expectOverlap {
            _ = try SnapshotBuild.pack(
                release: scratch.url("models/release"),
                into: scratch.url("models"),
                plan: try Self.plan(),
                sourceName: "test/release",
                freeSpaceBytes: 0,
                note: { _ in },
                shouldContinue: {})
        }
        #expect(
            scratch.hasFile("models/release/transformer/model.safetensors"),
            "the destination holding the source must not have been emptied for the rename")
        #expect(!scratch.hasFile("models.partial"))
    }

    /// Runs `build` and records a failure unless it threw the overlap refusal.
    private static func expectOverlap(_ build: () throws -> Void) {
        do {
            try build()
            Issue.record("the build ran instead of refusing the overlap")
        } catch QuantizationError.destinationOverlapsSource {
        } catch {
            Issue.record("expected the overlap refusal, got \(error)")
        }
    }

    /// A release with one component whose shard is an empty file, at `path` under the scratch.
    private static func release(at path: String = "release") throws -> Scratch {
        let scratch = Scratch("SnapshotQuantizer")
        try scratch.write("{}", to: "\(path)/model_index.json")
        try scratch.make("\(path)/transformer/model.safetensors")
        return scratch
    }

    private static func plan() throws -> QuantizationPlan {
        QuantizationPlan(
            components: [
                QuantizedComponent(
                    directoryName: "transformer",
                    fallback: try QuantizationPrecision(bits: 4, groupSize: 64))
            ],
            verbatimDirectories: []
        )
    }
}
