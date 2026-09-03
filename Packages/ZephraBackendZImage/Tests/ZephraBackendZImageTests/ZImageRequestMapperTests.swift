import Foundation
import Testing
import ZImage
import ZephraCore

@testable import ZephraBackendZImage

@Suite("ZImageRequestMapper")
struct ZImageRequestMapperTests {
    private let descriptor = ModelCatalog.zImageTurbo8bit
    private let snapshot = URL(fileURLWithPath: "/tmp/zephra-test-snapshot")

    private func settings(
        prompt: String = "a quiet room",
        negative: String? = nil,
        size: ImageSize = ImageSize(width: 1024, height: 1024),
        steps: Int = 9,
        guidance: Double = 0,
        seed: UInt64 = 42
    ) -> GenerationSettings {
        GenerationSettings(
            prompt: prompt,
            negativePrompt: negative,
            size: size,
            steps: steps,
            guidance: guidance,
            seed: seed
        )
    }

    /// The mapper only throws on a reference image it cannot open, and no test here passes one
    /// it cannot, so the tests that are about arithmetic keep reading as one expression.
    private func request(_ settings: GenerationSettings, _ model: ModelDescriptor? = nil)
        -> ZImageGenerationRequest
    {
        try! ZImageRequestMapper.request(
            for: settings, descriptor: model ?? descriptor, snapshot: snapshot
        )
    }

    @Test("settings that already fit the model pass through untouched")
    func acceptableSettingsSurvive() {
        let made = request(settings())
        #expect(made.prompt == "a quiet room")
        #expect(made.width == 1024)
        #expect(made.height == 1024)
        #expect(made.steps == 9)
        #expect(made.seed == 42)
    }

    @Test("sizes are pulled onto the model's 16-pixel grid")
    func sizesAreAligned() {
        let made = request(settings(size: ImageSize(width: 1020, height: 780)))
        #expect(made.width == 1024)
        #expect(made.height == 784)
        #expect(made.width % 16 == 0 && made.height % 16 == 0)
    }

    @Test("sizes outside the model's range come back inside it, still on the grid")
    func sizesAreBounded() {
        let small = request(settings(size: ImageSize(width: 64, height: 300)))
        #expect(small.width == 512)
        #expect(small.height == 512)

        let large = request(settings(size: ImageSize(width: 4000, height: 3000)))
        #expect(large.width == 2048)
        #expect(large.height == 2048)
    }

    @Test("step counts and guidance are clamped to what the model tolerates")
    func stepsAndGuidanceAreClamped() {
        #expect(request(settings(steps: 500)).steps == 20)
        #expect(request(settings(steps: 0)).steps == 1)
        // Z-Image Turbo is distilled: its guidance range is a single point at zero.
        #expect(request(settings(guidance: 7.5)).guidanceScale == 0)
    }

    @Test("a negative prompt the model would ignore is dropped rather than sent")
    func unsupportedNegativePromptIsDropped() {
        #expect(descriptor.capabilities.supportsNegativePrompt == false)
        #expect(request(settings(negative: "blurry")).negativePrompt == nil)
    }

    @Test("the seed is carried through, and withheld from models that cannot use it")
    func seedFollowsCapability() {
        #expect(request(settings(seed: .max)).seed == .max)
        #expect(request(settings(seed: 7), seedlessModel).seed == nil)
    }

    @Test("the model is always the resolved snapshot, never the pipeline's own default")
    func modelIsTheResolvedSnapshot() {
        let made = request(settings())
        #expect(made.model == snapshot.path)
        #expect(made.maxSequenceLength == 512)
    }

    @Test("the unused output path is a temporary file named for the model")
    func outputPathIsAThrowawayTemporary() {
        let path = request(settings()).outputPath
        #expect(path.deletingLastPathComponent().path == FileManager.default.temporaryDirectory.path)
        #expect(path.lastPathComponent == "zephra-\(descriptor.id)-unused.png")
    }

    /// A stand-in for a future model that cannot reproduce a seed, so the mapper's capability
    /// check is exercised rather than assumed.
    private var seedlessModel: ModelDescriptor {
        let base = descriptor.capabilities
        let capabilities = ModelCapabilities(
            sizeAlignment: base.sizeAlignment,
            sizePresets: base.sizePresets,
            sizeBounds: base.sizeBounds,
            defaultSize: base.defaultSize,
            stepBounds: base.stepBounds,
            defaultSteps: base.defaultSteps,
            guidanceBounds: base.guidanceBounds,
            defaultGuidance: base.defaultGuidance,
            supportsNegativePrompt: base.supportsNegativePrompt,
            supportsSeed: false
        )
        return ModelDescriptor(
            id: "seedless",
            displayName: "Seedless",
            variantName: nil,
            backend: .zImage,
            source: descriptor.source,
            quantization: descriptor.quantization,
            downloadBytes: descriptor.downloadBytes,
            residentBytes: descriptor.residentBytes,
            peakBytes: descriptor.peakBytes,
            tiledPeakBytes: descriptor.tiledPeakBytes,
            maxPromptTokens: descriptor.maxPromptTokens,
            capabilities: capabilities
        )
    }
}
