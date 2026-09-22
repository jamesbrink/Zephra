import Foundation
import QwenImage21
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraBackendQwenImage21

@Suite("Availability is answered from the disk alone")
struct QwenImage21AvailabilityTests {
    @Test("a local directory is available once every entry is there, and says what is missing until then")
    func localDirectory() async throws {
        let scratch = Scratch()
        let directory = try scratch.make("qwen21", isDirectory: true)
        let descriptor = QwenImage21ModelUnderTest.local(directory)
        let backend = QwenImage21Backend()
        let locations = ModelLocations(root: scratch.url("models"))

        let before = await backend.availability(of: descriptor, locations: locations)
        #expect(before.reason?.contains("quantization.json") == true)
        try Self.packed(scratch, at: "qwen21")
        #expect(await backend.availability(of: descriptor, locations: locations) == .available)
    }

    @Test("a hub model without a cached release needs a download and a build")
    func hubModelWithNothingCached() async throws {
        let scratch = Scratch()
        #expect(
            await QwenImage21Backend().availability(
                of: QwenImage21ModelUnderTest.hub(),
                locations: ModelLocations(root: scratch.url("models")))
                == .needsDownloadAndBuild(bytes: 16))
    }

    @Test("the release in the models folder means a build and no network")
    func aDownloadedReleaseNeedsOnlyABuild() async throws {
        let scratch = Scratch()
        let locations = ModelLocations(root: scratch.url("models"))
        try Self.release(scratch, at: "models/Downloads/nobody--no-such-model")

        #expect(
            await QwenImage21Backend().availability(
                of: QwenImage21ModelUnderTest.hub(), locations: locations) == .needsBuild)
    }

    @Test("once the variant is packed, the release is beside the point")
    func aPackedVariantIsAvailable() async throws {
        let scratch = Scratch()
        let locations = ModelLocations(root: scratch.url("models"))
        try Self.packed(scratch, at: "models/qwen-image-2.1-availability-test")

        #expect(
            await QwenImage21Backend().availability(
                of: QwenImage21ModelUnderTest.hub(), locations: locations) == .available)
    }

    @Test("a half-written build, every directory there but the manifest, is not available")
    func aBuildStoppedBeforeItsManifestIsNotAvailable() async throws {
        let scratch = Scratch()
        let locations = ModelLocations(root: scratch.url("models"))
        for part in QwenImage21SnapshotLayout.directories {
            try scratch.make("models/qwen-image-2.1-availability-test/\(part)", isDirectory: true)
        }

        #expect(
            await QwenImage21Backend().availability(
                of: QwenImage21ModelUnderTest.hub(), locations: locations)
                == .needsDownloadAndBuild(bytes: 16))
    }

    /// A directory holding what a packed 2.1 variant must have.
    private static func packed(_ scratch: Scratch, at path: String) throws {
        try scratch.write("{}", to: "\(path)/quantization.json")
        for part in QwenImage21SnapshotLayout.directories {
            try scratch.make("\(path)/\(part)", isDirectory: true)
        }
    }

    /// A directory holding every file the packer reads out of the 2.1 release.
    private static func release(_ scratch: Scratch, at path: String) throws {
        // A real index, not `{}`: the completeness check holds the directory to every component
        // its index names, so an empty one would say the release is not there at all.
        try scratch.write(
            """
            {"_class_name": "QwenImage21Pipeline", \
            "transformer": ["diffusers", "QwenImage21Transformer2DModel"], \
            "text_encoder": ["transformers", "Qwen3VLForConditionalGeneration"], \
            "vae": ["diffusers", "AutoencoderKLQwenImage21"], \
            "processor": ["transformers", "Qwen3VLProcessor"], \
            "scheduler": ["diffusers", "FlowMatchEulerDiscreteScheduler"]}
            """, to: "\(path)/model_index.json")
        for entry in QwenImage21SnapshotLayout.releaseEntries where entry != "model_index.json" {
            try scratch.write("{}", to: "\(path)/\(entry)")
        }
    }
}
