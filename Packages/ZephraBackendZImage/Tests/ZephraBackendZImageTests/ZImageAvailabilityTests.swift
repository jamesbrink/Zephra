import Foundation
import Testing
import ZephraCore

@testable import ZephraBackendZImage

@Suite("ZImage availability")
struct ZImageAvailabilityTests {
    @Test("a local directory that was never built is missing, and says what it lacks")
    func localDirectoryThatIsNotThere() async throws {
        let scratch = Scratch("ZImageAvailability")
        let descriptor = Self.local(at: scratch.url("never-built"))
        let availability = await ZImageBackend().availability(of: descriptor)
        #expect(availability.isObtainable == false)
        #expect(availability.label == "Not built yet")
        #expect(availability.reason?.contains("model_index.json") == true)
    }

    @Test("a local directory with every entry the loader opens is available")
    func localDirectoryThatIsComplete() async throws {
        let scratch = Scratch("ZImageAvailability")
        try scratch.make("built/model_index.json")
        for part in ["transformer", "text_encoder", "vae"] {
            try scratch.make("built/\(part)", isDirectory: true)
        }
        let descriptor = Self.local(at: scratch.url("built"))
        #expect(await ZImageBackend().availability(of: descriptor) == .available)
    }

    /// The catalog's default model, pointed at a local directory instead of the hub.
    private static func local(at directory: URL) -> ModelDescriptor {
        let base = ModelCatalog.default
        return ModelDescriptor(
            id: "local-test",
            displayName: base.displayName,
            variantName: base.variantName,
            backend: base.backend,
            source: .localDirectory(directory),
            quantization: base.quantization,
            downloadBytes: 0,
            residentBytes: base.residentBytes,
            peakBytes: base.peakBytes,
            tiledPeakBytes: base.tiledPeakBytes,
            maxPromptTokens: base.maxPromptTokens,
            capabilities: base.capabilities
        )
    }
}
