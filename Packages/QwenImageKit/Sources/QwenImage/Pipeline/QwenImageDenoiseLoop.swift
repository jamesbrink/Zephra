import CoreGraphics
import Foundation
import MLX

/// The denoising ladder: packed noise in, packed latents out.
///
/// Split out of `QwenImagePipeline` because it is the one part of a generation that changes
/// shape depending on how the run starts. From a prompt alone it walks the whole ladder; from a
/// reference picture it joins partway down, and everything either side of it — the tokenizer,
/// the text encoder, the autoencoder's decode — is the same job either way.
enum QwenImageDenoiseLoop {
    /// A picture to start from, and how far the generation may travel from it.
    struct Reference {
        let image: CGImage
        let strength: Double
        let width: Int
        let height: Int
    }

    /// Runs the ladder and returns the final latents, still packed.
    ///
    /// With a `reference`, the loop starts at the first step whose sigma is at or below its
    /// strength, from that picture's latent carrying that step's share of `noise`. Progress is
    /// reported against the full step count either way, so a host drawing one segment per step
    /// shows the skipped ones as finished rather than showing a shorter run.
    static func run(
        noise: MLXArray,
        reference: Reference?,
        scheduler: FlowMatchEulerScheduler,
        transformer: QwenImageTransformer,
        autoencoder: QwenImageAutoencoder,
        conditioning: MLXArray,
        frequencies: (image: RotaryFrequencies, text: RotaryFrequencies),
        onProgress: (QwenImageGenerationProgress) -> Void
    ) throws -> MLXArray {
        let sigmas = scheduler.sigmas.dropLast()
        var latents = noise
        var startIndex = 0

        if let reference {
            startIndex = QwenImageReferenceLatents.startIndex(
                sigmas: scheduler.sigmas, strength: reference.strength, steps: sigmas.count)
            let pixels = try QwenPixelBuffer.pixels(
                from: reference.image, width: reference.width, height: reference.height)
            let encoded = QwenImageLatentPacking.pack(autoencoder.encode(pixels))
            latents = QwenImageReferenceLatents.mixed(
                reference: encoded, noise: noise, sigma: scheduler.sigmas[startIndex])
            MLX.eval(latents)
        }

        // The model is conditioned on the noise level itself, on its zero-to-one scale; the
        // reference multiplies by a thousand and divides it back out before the embedding.
        for (index, sigma) in sigmas.enumerated().dropFirst(startIndex) {
            try Task.checkCancellation()
            onProgress(
                QwenImageGenerationProgress(stage: .denoising(step: index, of: sigmas.count)))
            let prediction = transformer(
                latents: latents,
                text: conditioning,
                timestep: MLXArray([Float(sigma)]),
                frequencies: frequencies
            )
            latents = scheduler.step(modelOutput: prediction, index: index, sample: latents)
            MLX.eval(latents)
        }
        return latents
    }
}
