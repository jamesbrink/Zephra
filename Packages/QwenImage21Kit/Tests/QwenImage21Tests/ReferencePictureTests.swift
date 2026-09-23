import CoreGraphics
import Foundation
import ImageIO
import MLX
import Testing
import UniformTypeIdentifiers

@testable import QwenImage21

/// The one resize every reference picture goes through on its way in.
///
/// Both halves of the model read the same resized copy, so the size it lands on has to satisfy
/// both: the tower's own `smart_resize` must find nothing to do — `Qwen3VLImagePreprocessing`
/// throws otherwise — and the autoencoder needs both edges on its sixteen-pixel grid. A
/// multiple of 32 is what satisfies both, and it is what `calculate_dimensions` produces.
@Suite("A reference picture is decoded and fitted once, alpha and all")
struct ReferencePictureTests {
    /// The published `processor/preprocessor_config.json`, as the fields this kit reads.
    ///
    /// Stated rather than loaded, so the suite runs on a Mac with no release; the suite that
    /// reads the real file checks these are the published numbers.
    static func publishedProcessor() throws -> QwenImage21ProcessorConfiguration {
        try JSONDecoder().decode(
            QwenImage21ProcessorConfiguration.self,
            from: Data(
                """
                {"patch_size": 16, "merge_size": 2, "temporal_patch_size": 2,
                 "image_mean": [0.5, 0.5, 0.5], "image_std": [0.5, 0.5, 0.5],
                 "rescale_factor": 0.00392156862745098, "resample": 3,
                 "size": {"shortest_edge": 65536, "longest_edge": 16777216}}
                """.utf8))
    }

    /// A PNG of `width` by `height` with a hard alpha edge down the middle: opaque red on the
    /// left, fully transparent on the right.
    static func png(width: Int, height: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let opaque = column < width / 2
                bytes[offset] = opaque ? 255 : 0
                bytes[offset + 3] = opaque ? 255 : 0
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(
            CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test("a square picture lands on the square multiple of 32 nearest a megapixel")
    func squareFit() throws {
        let fitted = try QwenImage21ReferencePicture.fitted(try Self.png(width: 700, height: 700))
        #expect(fitted.shape == [1024, 1024, 4])
    }

    @Test("a wide picture keeps its aspect within one 32-pixel step of it")
    func wideFit() throws {
        let fitted = try QwenImage21ReferencePicture.fitted(try Self.png(width: 640, height: 360))
        let (height, width) = (fitted.dim(0), fitted.dim(1))
        #expect(width % 32 == 0 && height % 32 == 0)
        // `calculate_dimensions(1024², 16/9)` is 1376 x 768 — the reference's own arithmetic,
        // which `ImageFittingTests` pins separately against the six dumped shapes.
        #expect(
            QwenImage21ImageFitting.dimensions(ratio: 640.0 / 360.0)
                == QwenImage21ImageFitting.Target(width: width, height: height))
        #expect(abs(Double(width) / Double(height) - 640.0 / 360.0) < 0.05)
    }

    @Test("the fitted size is a whole number of latent cells and of tower patch blocks")
    func bothHalvesAccept() throws {
        let fitted = try QwenImage21ReferencePicture.fitted(try Self.png(width: 813, height: 611))
        // 32 is `vae_scale_factor * 2` and also `patch_size * merge_size`, which is the whole
        // reason one resize can feed both.
        #expect(fitted.dim(0) % 32 == 0 && fitted.dim(1) % 32 == 0)
        let processor = try Self.publishedProcessor()
        let (patches, grid) = try Qwen3VLImagePreprocessing.patches(
            of: Qwen3VLImagePreprocessing.towerInput(fitted), processor: processor)
        #expect(grid.rows == fitted.dim(0) / processor.patchSize)
        #expect(patches.dim(0) == grid.patchCount)
        // One vision-language slot per four latent cells, which is what lets the joint layout
        // expand a slot into four tokens.
        let latents = (fitted.dim(0) / 16) * (fitted.dim(1) / 16)
        #expect(grid.slotCount(mergeSize: processor.mergeSize) * 4 == latents)
    }

    @Test("alpha survives the resize as its own channel, and is not premultiplied into colour")
    func alphaSurvives() throws {
        let fitted = try QwenImage21ReferencePicture.fitted(try Self.png(width: 512, height: 512))
        let alpha = fitted[.ellipsis, 3]
        MLX.eval(alpha)
        #expect(alpha[0, 0].item(Float.self) == 255, "the opaque half")
        #expect(alpha[0, 1023].item(Float.self) == 0, "the transparent half")
        // Un-premultiplied: the opaque half's red is still 255 rather than scaled by its alpha.
        #expect(fitted[0, 0, 0].item(Float.self) == 255)
        #expect(fitted[0, 0, 1].item(Float.self) == 0)
    }

    @Test("bytes that are not a picture are refused rather than decoded as one")
    func unreadable() {
        #expect(throws: QwenImage21PipelineError.unreadableReference) {
            _ = try QwenImage21ReferencePicture.fitted(Data("not a picture".utf8))
        }
    }
}
