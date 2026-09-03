import Foundation
import MLX
import Testing

@testable import QwenImage

/// The encoder against the reference.
///
/// Three claims, and each of them fails silently rather than loudly if it is wrong.
///
/// The 3-D-to-2-D reduction, as for the decoder. The downsampler's asymmetric pad — the
/// reference pads only the bottom and right edge before striding, and padding evenly instead
/// shifts every feature half a cell. And the `time_conv` skip: the doll's house here has a
/// downsampler that carries one, and the reference does not run it for the first chunk of a
/// sequence, which a still image always is.
@Suite("VAE encoder parity")
struct VAEEncoderParityTests {
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

    private static func loaded() throws -> (QwenImageAutoencoder, [String: MLXArray]) {
        let fixture = try Fixture.load("vae")
        var weights: [String: MLXArray] = [:]
        for (key, value) in fixture where key.hasPrefix("vae.") {
            let name = String(key.dropFirst("vae.".count))
            guard !name.hasPrefix("in."), !name.hasPrefix("out.") else { continue }
            weights[name] = value
        }
        let autoencoder = QwenImageAutoencoder(try configuration.validated())
        try autoencoder.load(weights: weights)
        MLX.eval(autoencoder.parameters())
        return (autoencoder, fixture)
    }

    @Test("the encoder matches the reference on the doll's-house picture")
    func encodeMatchesReference() throws {
        let (autoencoder, fixture) = try Self.loaded()

        // The fixture's picture is [batch, channels, frames, height, width]; a still is one
        // frame, and this port works channels-last.
        let pixels = try #require(fixture["vae.in.pixels"])
            .squeezed(axis: 2)
            .transposed(0, 2, 3, 1)
        let latent = autoencoder.encode(pixels)

        let reference = try #require(fixture["vae.out.latent"]).squeezed(axis: 2)
        #expect(latent.shape == reference.shape)
        let difference = Fixture.maxAbsoluteDifference(latent, reference)
        #expect(difference < 1e-4, "latents differ by \(difference)")
    }

    @Test("the encoder halves each spatial axis once per downsampler")
    func spatialScaleIsWhatTheConfigurationSays() throws {
        let (autoencoder, fixture) = try Self.loaded()
        let pixels = try #require(fixture["vae.in.pixels"]).squeezed(axis: 2)
            .transposed(0, 2, 3, 1)
        let latent = autoencoder.encode(pixels)

        let scale = Self.configuration.spatialScale
        #expect(latent.shape[2] == pixels.shape[1] / scale)
        #expect(latent.shape[3] == pixels.shape[2] / scale)
        #expect(latent.shape[1] == Self.configuration.zDim, "the mode, not mean and log-variance")
    }

    @Test("encoding then decoding lands back in the picture's own units")
    func encodeThenDecodeIsTheSameScale() throws {
        let (autoencoder, fixture) = try Self.loaded()
        let pixels = try #require(fixture["vae.in.pixels"]).squeezed(axis: 2)
            .transposed(0, 2, 3, 1)

        let round = autoencoder.decode(autoencoder.encode(pixels))
        #expect(round.shape == pixels.shape)
        // Not a claim about fidelity — an untrained doll's house reconstructs nothing — only
        // that the two halves agree about shape and about the -1 to 1 range they work in.
        #expect(MLX.max(MLX.abs(round)).item(Float.self) <= 1.0001)
    }
}
