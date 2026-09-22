import Foundation
import MLX
import Testing
import ZephraMLX

@testable import QwenImage

/// A frame of a run in flight, on a doll's-house autoencoder.
///
/// Random weights, because nothing here is about the pixels: what is under test is that the
/// tokens are unpacked before they are pooled, that the pooling is applied at all, and that the
/// bytes handed back are the size the frame says they are.
@Suite("A preview frame of a Qwen-Image run")
struct LatentPreviewTests {
    /// Two stages and four latent channels, so the decoder doubles rather than octuples and a
    /// whole frame is a few thousand pixels.
    private static let configuration = QwenImageVAEConfiguration(
        baseDim: 8,
        zDim: 4,
        dimMult: [1, 2],
        numResBlocks: 1,
        attnScales: [],
        temperalDownsample: [true],
        latentsMean: [0.1, -0.2, 0.3, -0.4],
        latentsStd: [1.5, 0.8, 1.2, 0.9]
    )

    static func autoencoder() throws -> QwenImageAutoencoder {
        let model = QwenImageAutoencoder(try configuration.validated())
        MLX.eval(model.parameters())
        return model
    }

    @Test("the frame is the pooled latent decoded, and its bytes are four to a pixel")
    func theFrameIsPooledAndDecoded() throws {
        let model = try Self.autoencoder()
        // 40 by 64 latent cells, which is a 320 by 512 image on the published model.
        let (latentHeight, latentWidth) = (40, 64)
        let tokens = MLXArray.zeros(
            [1, QwenImageLatentPacking.tokenCount(
                latentHeight: latentHeight, latentWidth: latentWidth), 16],
            type: Float.self)

        let frame = try QwenImageLatentPreview.make(
            tokens: tokens, latentHeight: latentHeight, latentWidth: latentWidth,
            autoencoder: model)

        // The long edge is over the 32-cell limit, so the factor is two.
        #expect(LatentPreview.poolingFactor(height: latentHeight, width: latentWidth) == 2)
        let expected = model.decodeUntiled(
            LatentPreview.pooled(
                QwenImageLatentPacking.unpack(
                    tokens, height: latentHeight, width: latentWidth),
                by: 2))
        #expect(frame.height == expected.dim(1))
        #expect(frame.width == expected.dim(2))
        #expect(frame.pixels.count == frame.width * frame.height * 4)
    }

    @Test("every fourth byte is opaque, and the frame is not empty")
    func theBytesAreAnImage() throws {
        let model = try Self.autoencoder()
        let tokens = MLXArray.zeros(
            [1, QwenImageLatentPacking.tokenCount(latentHeight: 16, latentWidth: 16), 16],
            type: Float.self)

        let frame = try QwenImageLatentPreview.make(
            tokens: tokens, latentHeight: 16, latentWidth: 16, autoencoder: model)

        let bytes = Array(frame.pixels)
        #expect(!bytes.isEmpty)
        #expect(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 })
    }
}
