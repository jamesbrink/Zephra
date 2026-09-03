import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraBackendFlux2

@Suite("Availability is answered from the disk alone")
struct Flux2AvailabilityTests {
    @Test("a local directory is available once every entry is there, and says what is missing until then")
    func localDirectory() async throws {
        let scratch = Scratch()
        let directory = try scratch.make("klein", isDirectory: true)
        let descriptor = ModelDescriptor(
            id: "klein-test", displayName: "klein", variantName: nil, backend: .flux2,
            source: .localDirectory(directory), quantization: .int4, downloadBytes: 0,
            residentBytes: 1, peakBytes: 2, tiledPeakBytes: 2, maxPromptTokens: 512,
            capabilities: ModelCatalog.flux2Klein4bit.capabilities)
        let backend = Flux2Backend()
        let before = await backend.availability(of: descriptor)
        #expect(before.reason?.contains("quantization.json") == true)
        for entry in ["quantization.json", "transformer", "text_encoder", "vae", "tokenizer", "scheduler"] {
            let url = directory.appending(path: entry)
            if entry.hasSuffix(".json") {
                try Data("{}".utf8).write(to: url)
            } else {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
        #expect(await backend.availability(of: descriptor) == .available)
    }

    @Test("a hub model without a cached release needs a download and a build")
    func hubModelWithNothingCached() async throws {
        let descriptor = ModelDescriptor(
            id: "flux2-klein-availability-test", displayName: "klein", variantName: nil,
            backend: .flux2,
            source: .huggingFace(repoID: "nobody/no-such-model", revision: "main", filePatterns: ["*"]),
            quantization: .int4, downloadBytes: 16, residentBytes: 1, peakBytes: 2,
            tiledPeakBytes: 2, maxPromptTokens: 512,
            capabilities: ModelCatalog.flux2Klein4bit.capabilities, builtBytes: 4)
        let backend = Flux2Backend()
        #expect(await backend.availability(of: descriptor) == .needsDownloadAndBuild(bytes: 16))
    }
}
