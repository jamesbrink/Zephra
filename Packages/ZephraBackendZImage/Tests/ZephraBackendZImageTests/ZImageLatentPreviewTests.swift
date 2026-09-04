import Foundation
import MLX
import Testing
import ZImage

/// A frame of a Z-Image run in flight, on a doll's-house autoencoder.
///
/// It lives in this package rather than in `ZImageKit` because the vendored package carries no
/// test target and adding one would be another thing to reconcile at every re-sync.
///
/// Random weights, because nothing here is about the pixels: what is under test is that the
/// latent is pooled before it is decoded, and that the bytes handed back are the size the frame
/// says they are.
@Suite("A preview frame of a Z-Image run")
struct ZImageLatentPreviewTests {
    /// Two stages and four latent channels, so the decoder doubles rather than octuples and a
    /// whole frame is a few thousand pixels.
    static func autoencoder() -> AutoencoderKL {
        let model = AutoencoderKL(
            configuration: VAEConfig(
                latentChannels: 4,
                blockOutChannels: [8, 16],
                layersPerBlock: 1,
                normNumGroups: 4
            ))
        MLX.eval(model.parameters())
        return model
    }

    @Test("the frame is the pooled latent decoded, and its bytes are four to a pixel")
    func theFrameIsPooledAndDecoded() {
        let model = Self.autoencoder()
        // 40 by 64 latent cells, which is a 320 by 512 image on the published model.
        let latents = MLXArray.zeros([1, 4, 40, 64], type: Float.self)

        let frame = ZImageLatentPreview.make(latents: latents, vae: model)

        // The long edge is over the 32-cell limit, so the factor is two.
        #expect(ZImageLatentPreview.poolingFactor(height: 40, width: 64) == 2)
        let expected = model.decodeUntiled(ZImageLatentPreview.pooled(latents, by: 2))
        #expect(frame.height == expected.dim(1))
        #expect(frame.width == expected.dim(2))
        #expect(frame.pixels.count == frame.width * frame.height * 4)
    }

    @Test("a latent already under the limit is decoded as it stands")
    func smallLatentsAreNotPooled() {
        let model = Self.autoencoder()
        let latents = MLXArray.zeros([1, 4, 16, 16], type: Float.self)

        let frame = ZImageLatentPreview.make(latents: latents, vae: model)

        #expect(ZImageLatentPreview.poolingFactor(height: 16, width: 16) == 1)
        #expect(frame.width == model.decodeUntiled(latents).dim(2))
        let bytes = Array(frame.pixels)
        #expect(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 })
    }
}
