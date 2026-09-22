import Foundation
import MLX
import Testing

@testable import QwenImage21

/// How a reference picture reaches the tower, against the reference's own processor.
///
/// Three claims. `smart_resize` is the arithmetic the published bounds imply, including
/// Python's round-half-to-even, and it is a no-op for a picture the pipeline has already fitted
/// — which is why the port refuses a picture it is not a no-op for rather than carrying a
/// second resampler. The patchify is block-major with the still picture repeated along the
/// frame axis, giving patch vectors of `channels * frames * patch²`. And the alpha goes over
/// **white**, for this copy only.
@Suite("A reference picture is prepared the way the processor prepares it")
struct ImagePreprocessingTests {
    @Test("smart_resize answers what the reference answers at the published bounds")
    func smartResizeMatchesTheReference() throws {
        let fixture = try Fixture.load("vision")
        let inputs = try #require(fixture["resize.in"]).asArray(Int32.self)
        let outputs = try #require(fixture["resize.out"]).asArray(Int32.self)

        for index in stride(from: 0, to: inputs.count, by: 2) {
            let fitted = try Qwen3VLImagePreprocessing.fitted(
                height: Int(inputs[index]), width: Int(inputs[index + 1]),
                factor: 32, minPixels: 65536, maxPixels: 16_777_216)
            #expect(
                [Int32(fitted.height), Int32(fitted.width)]
                    == [outputs[index], outputs[index + 1]],
                Comment(
                    rawValue:
                        "\(inputs[index])x\(inputs[index + 1]) gave \(fitted), wanted "
                        + "\(outputs[index])x\(outputs[index + 1])"))
        }
    }

    @Test("a picture the pipeline already fitted passes through untouched")
    func aFittedPictureIsANoOp() throws {
        // Every size `calculate_dimensions(1024², ratio)` answers is a multiple of 32 and well
        // inside the bounds, so the tower's own resize never moves one. That is the whole
        // reason this port needs no second resampler.
        for (height, width) in [(1024, 1024), (768, 1344), (1152, 896), (640, 1536)] {
            let fitted = try Qwen3VLImagePreprocessing.fitted(
                height: height, width: width, factor: 32, minPixels: 65536, maxPixels: 16_777_216)
            #expect(fitted.height == height && fitted.width == width)
        }
    }

    @Test("a picture that is not on the grid is refused rather than quietly cropped")
    func anUnfittedPictureIsRefused() throws {
        let picture = MLXArray.zeros([70, 96, 3], type: Float.self)
        #expect(throws: Qwen3VLEncodingError.sizeNotFitted(height: 70, width: 96, factor: 8)) {
            _ = try Qwen3VLImagePreprocessing.patches(
                of: picture, processor: try Qwen3VLDollHouse.processor())
        }
    }

    @Test("the patchify is the processor's, block-major and doubled along the frame axis")
    func thePatchifyMatchesTheProcessor() throws {
        let fixture = try Fixture.load("vision")
        let image = try #require(fixture["patchify.in.image"])
        let reference = try #require(fixture["patchify.out.patches"])
        let referenceGrid = try #require(fixture["patchify.out.grid"]).asArray(Int32.self)

        let (patches, grid) = try Qwen3VLImagePreprocessing.patches(
            of: image, processor: try Qwen3VLDollHouse.processor())

        #expect(grid.thw.map(Int32.init) == referenceGrid)
        #expect(patches.shape == reference.shape)
        let difference = Fixture.maxAbsoluteDifference(patches, reference)
        #expect(difference < 1e-5, Comment(rawValue: "the patches differ by \(difference)"))
    }

    @Test("the alpha is flattened over white, not dropped and not premultiplied by black")
    func theAlphaGoesOverWhite() throws {
        let fixture = try Fixture.load("vision")
        let rgba = try #require(fixture["white.in.rgba"])
        let reference = try #require(fixture["white.out.rgb"])

        let flattened = Qwen3VLImagePreprocessing.towerInput(rgba)
        #expect(flattened.shape == reference.shape)
        // Exact: the reference's blend is PIL's integer paste and this one is a rounded float
        // lerp, and on eight-bit inputs they are the same number.
        #expect(Fixture.maxAbsoluteDifference(flattened, reference) == 0)

        // A three-channel picture is already the tower's copy and is not touched.
        let rgb = MLXArray.zeros([4, 4, 3], type: Float.self)
        #expect(Qwen3VLImagePreprocessing.towerInput(rgb).shape == [4, 4, 3])
    }

    @Test("a picture longer than two hundred times its shortest edge is refused")
    func anExtremeAspectIsRefused() {
        #expect(throws: Qwen3VLEncodingError.aspectRatioTooExtreme(height: 4, width: 4096)) {
            _ = try Qwen3VLImagePreprocessing.fitted(
                height: 4, width: 4096, factor: 32, minPixels: 65536, maxPixels: 16_777_216)
        }
    }
}
