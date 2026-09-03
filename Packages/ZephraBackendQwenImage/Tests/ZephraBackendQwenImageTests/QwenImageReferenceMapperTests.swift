import CoreGraphics
import Foundation
import ImageIO
import QwenImage
import Testing
import UniformTypeIdentifiers
import ZephraCore

@testable import ZephraBackendQwenImage

@Suite("QwenImageRequestMapper, reference images")
struct QwenImageReferenceMapperTests {
    private let descriptor = ModelCatalog.qwenImage2512_4bit
    private let folder = URL(filePath: NSTemporaryDirectory())
        .appending(path: "QwenReferenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func settings(reference: ReferenceImage?) -> GenerationSettings {
        GenerationSettings(
            prompt: "a quiet room",
            size: ImageSize(width: 1024, height: 1024),
            steps: 4,
            guidance: 0,
            seed: 42,
            reference: reference
        )
    }

    private func request(
        _ settings: GenerationSettings, _ model: ModelDescriptor? = nil
    ) throws -> QwenImageGenerationRequest {
        try QwenImageRequestMapper.request(for: settings, descriptor: model ?? descriptor)
    }

    @Test("no reference means no reference, and the strength that runs every step")
    func noReference() throws {
        let made = try request(settings(reference: nil))
        #expect(made.referenceImage == nil)
        #expect(made.referenceStrength == 1)
    }

    @Test("a reference picture is decoded and carried through with its strength")
    func referenceIsCarried() throws {
        let url = try writePNG(width: 24, height: 16)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try request(settings(reference: ReferenceImage(url: url, strength: 0.45)))

        let image = try #require(made.referenceImage)
        #expect(image.width == 24 && image.height == 16, "unscaled; the pipeline resizes")
        #expect(made.referenceStrength == 0.45)
    }

    @Test("a strength outside the model's bounds arrives inside them")
    func strengthIsClamped() throws {
        let url = try writePNG(width: 8, height: 8)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(descriptor.capabilities.referenceStrengthBounds == 0.1...0.9)
        #expect(try request(settings(reference: .init(url: url, strength: 2))).referenceStrength == 0.9)
        #expect(try request(settings(reference: .init(url: url, strength: 0))).referenceStrength == 0.1)
    }

    @Test("a model that cannot start from a picture is never handed one")
    func unsupportedModelDropsTheReference() throws {
        let url = try writePNG(width: 8, height: 8)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try request(
            settings(reference: ReferenceImage(url: url, strength: 0.5)), Self.referencelessModel
        )
        #expect(made.referenceImage == nil)
        #expect(made.referenceStrength == 1)
    }

    @Test("a reference that will not open fails before any denoising starts")
    func unreadableReferenceThrows() {
        let missing = folder.appending(path: "not-a-picture.png")
        #expect(throws: ReferenceImageDecoding.Failure.self) {
            try request(settings(reference: ReferenceImage(url: missing, strength: 0.5)))
        }
    }

    /// A real PNG on disk, because the mapper's job is to open one.
    private func writePNG(width: Int, height: Int) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "harbour.png")
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// A stand-in for a model with no image encoder, so the drop is exercised: both models the
    /// catalog ships can start from a picture.
    private static let referencelessModel: ModelDescriptor = {
        let base = ModelCatalog.qwenImage2512_4bit
        let capabilities = ModelCapabilities(
            sizeAlignment: base.capabilities.sizeAlignment,
            sizePresets: base.capabilities.sizePresets,
            sizeBounds: base.capabilities.sizeBounds,
            defaultSize: base.capabilities.defaultSize,
            stepBounds: base.capabilities.stepBounds,
            defaultSteps: base.capabilities.defaultSteps,
            guidanceBounds: base.capabilities.guidanceBounds,
            defaultGuidance: base.capabilities.defaultGuidance,
            supportsNegativePrompt: base.capabilities.supportsNegativePrompt,
            supportsSeed: base.capabilities.supportsSeed,
            supportsReferenceImage: false
        )
        return ModelDescriptor(
            id: "referenceless",
            displayName: "Referenceless",
            variantName: nil,
            backend: .qwenImage,
            source: base.source,
            quantization: base.quantization,
            downloadBytes: base.downloadBytes,
            residentBytes: base.residentBytes,
            peakBytes: base.peakBytes,
            tiledPeakBytes: base.tiledPeakBytes,
            maxPromptTokens: base.maxPromptTokens,
            capabilities: capabilities
        )
    }()
}
