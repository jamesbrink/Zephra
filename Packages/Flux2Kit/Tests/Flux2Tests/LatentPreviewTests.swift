import Foundation
import MLX
import Testing
import ZephraMLX

@testable import Flux2

/// A frame of a run in flight, on the doll's-house autoencoder.
///
/// Random weights, because nothing here is about the pixels: what is under test is that the
/// tokens are unpacked before they are pooled, that the pooling is applied at all, and that the
/// bytes handed back are the size the frame says they are.
@Suite("A preview frame of a klein run")
struct LatentPreviewTests {
    /// Two stages and four latent channels, so the decoder doubles rather than octuples and a
    /// whole frame is a few thousand pixels.
    static func autoencoder() throws -> Flux2Autoencoder {
        let model = Flux2Autoencoder(try VAEParityTests.configuration())
        MLX.eval(model.parameters())
        return model
    }

    @Test("the frame is the pooled latent decoded, and its bytes are four to a pixel")
    func theFrameIsPooledAndDecoded() throws {
        let model = try Self.autoencoder()
        // A 20 by 32 grid of packed cells, which is a 320 by 512 image on the published model.
        let (packedHeight, packedWidth) = (20, 32)
        let tokens = MLXArray.zeros([1, packedHeight * packedWidth, 16], type: Float.self)

        let frame = try Flux2LatentPreview.make(
            tokens: tokens, packedHeight: packedHeight, packedWidth: packedWidth,
            autoencoder: model)

        // The unpacked latent is twice the packed grid, 40 by 64, so the long edge is over the
        // 32-cell limit and the factor is two.
        #expect(LatentPreview.poolingFactor(height: 40, width: 64) == 2)
        let expected = model.decodeUntiled(
            LatentPreview.pooled(model.unpacked(
                Flux2LatentPacking.grid(tokens, height: packedHeight, width: packedWidth)),
                by: 2))
        #expect(frame.height == expected.dim(1))
        #expect(frame.width == expected.dim(2))
        #expect(frame.pixels.count == frame.width * frame.height * 4)
    }

    @Test("every fourth byte is opaque, and none of them is off the end of the range")
    func theBytesAreAnImage() throws {
        let model = try Self.autoencoder()
        let tokens = MLXArray.zeros([1, 8 * 8, 16], type: Float.self)

        let frame = try Flux2LatentPreview.make(
            tokens: tokens, packedHeight: 8, packedWidth: 8, autoencoder: model)

        let bytes = Array(frame.pixels)
        #expect(!bytes.isEmpty)
        #expect(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 })
    }
}
