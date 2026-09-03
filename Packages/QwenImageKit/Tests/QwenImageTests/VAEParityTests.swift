import Foundation
import MLX
import Testing

@testable import QwenImage

/// The autoencoder against the reference.
///
/// The claim under test is the reduction this port makes: the reference decodes with 3-D causal
/// convolutions, and for a single frame every one of them reduces exactly to a 2-D convolution
/// over the kernel's last temporal slice. If that is wrong, the pixels differ.
@Suite("VAE parity")
struct VAEParityTests {
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

    private static func weights(_ fixture: [String: MLXArray]) -> [String: MLXArray] {
        var stripped: [String: MLXArray] = [:]
        for (key, value) in fixture where key.hasPrefix("vae.") {
            let name = String(key.dropFirst("vae.".count))
            guard !name.hasPrefix("in."), !name.hasPrefix("out.") else { continue }
            stripped[name] = value
        }
        return stripped
    }

    @Test("decoded pixels match the reference")
    func decodeMatchesReference() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = QwenImageAutoencoder(try Self.configuration.validated())
        try autoencoder.load(weights: Self.weights(fixture))
        MLX.eval(autoencoder.parameters())

        // The fixture's latent is [batch, channels, frames, height, width]; a still is one frame.
        let latent = try #require(fixture["vae.in.latent"]).squeezed(axis: 2)
        let pixels = autoencoder.decode(latent)

        // The reference keeps its frame axis, so drop it and put channels last to compare.
        let reference = try #require(fixture["vae.out.pixels"])
            .squeezed(axis: 2)
            .transposed(0, 2, 3, 1)
        #expect(pixels.shape == reference.shape)
        let difference = Fixture.maxAbsoluteDifference(pixels, reference)
        #expect(difference < 1e-4, "pixels differ by \(difference)")
    }

    @Test("the autoencoder loads every weight the reference carries, and nothing else")
    func weightNamesLineUp() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = QwenImageAutoencoder(Self.configuration)
        let ours = Set(autoencoder.parameters().flattened().map(\.0))
        // Both halves now: starting from a picture needs the encoder and `quant_conv`, so the
        // set is the whole checkpoint rather than the decoder's share of it.
        let theirs = Set(Self.weights(fixture).keys)
        #expect(
            theirs.subtracting(ours).isEmpty,
            "unloaded: \(theirs.subtracting(ours).sorted())")
        #expect(ours.subtracting(theirs).isEmpty,
            "unfilled: \(ours.subtracting(theirs).sorted())")
    }
}
