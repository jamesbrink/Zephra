import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraSnapshot

@Suite("What a packed variant's stamp says it was built from")
struct PackedProvenanceTests {
    /// Two descriptors alike but for the files their release is fetched with, which is the one
    /// thing that changed when LTX-2.5 grew a video encoder: the packed variant on a Mac that
    /// built one before is packed from a release that had no encoder in it, and reading it as
    /// current would load a model with no way to hold a first frame.
    static func model(patterns: [String]) -> ModelDescriptor {
        let base = ModelCatalog.default
        return ModelDescriptor(
            id: "packed-provenance-test", displayName: base.displayName,
            variantName: base.variantName, backend: base.backend,
            source: .huggingFace(repoID: "org/repo", revision: "main", filePatterns: patterns),
            quantization: base.quantization, downloadBytes: 9,
            residentBytes: base.residentBytes, peakBytes: base.peakBytes,
            tiledPeakBytes: base.tiledPeakBytes, maxPromptTokens: base.maxPromptTokens,
            capabilities: base.capabilities, builtBytes: 4)
    }

    @Test("a stamp written before a file was added to the release no longer matches the model")
    func aWiderPatternListMakesTheOldBuildStale() throws {
        let scratch = Scratch("PackedProvenance")
        let locations = ModelLocations(root: scratch.url("models"))
        let old = Self.model(patterns: ["a.safetensors"])
        let new = Self.model(patterns: ["a.safetensors", "b.safetensors"])
        let directory = locations.built(old)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try PackedProvenance.write(old, into: directory)
        #expect(PackedProvenance.matches(old, in: directory))
        #expect(
            !PackedProvenance.matches(new, in: directory),
            "a variant packed from the narrower release must read as something else")

        try PackedProvenance.write(new, into: directory)
        #expect(PackedProvenance.matches(new, in: directory))
    }

    @Test("the order the patterns are written in is not part of the identity")
    func patternsAreComparedSorted() throws {
        let scratch = Scratch("PackedProvenanceOrder")
        let directory = scratch.url("built")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try PackedProvenance.write(Self.model(patterns: ["b.json", "a.json"]), into: directory)
        #expect(PackedProvenance.matches(Self.model(patterns: ["a.json", "b.json"]), in: directory))
    }
}
