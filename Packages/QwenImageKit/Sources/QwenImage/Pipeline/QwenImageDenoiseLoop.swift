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
    /// With a `reference`, its strength buys a share of the steps and the loop enters that many
    /// from the end, from that picture's latent carrying that step's share of `noise`. Progress is
    /// reported against the full step count either way, so a host drawing one segment per step
    /// shows the skipped ones as finished rather than showing a shorter run.
    ///
    /// `latentSize` is the latent's own height and width in cells, which the loop needs only to
    /// hand a frame back the shape it was packed from; `onPreview` is that hook.
    static func run(
        noise: MLXArray,
        latentSize: (height: Int, width: Int),
        reference: Reference?,
        scheduler: FlowMatchEulerScheduler,
        transformer: QwenImageTransformer,
        autoencoder: QwenImageAutoencoder,
        conditioning: MLXArray,
        frequencies: (image: RotaryFrequencies, text: RotaryFrequencies),
        onProgress: (QwenImageGenerationProgress) -> Void,
        onPreview: QwenImagePipeline.PreviewHandler? = nil
    ) throws -> MLXArray {
        let sigmas = scheduler.sigmas.dropLast()
        var latents = noise
        var startIndex = 0

        if let reference {
            // The encode is a whole pass through the autoencoder, so a run cancelled while the
            // model was still loading should stop here rather than at the first step.
            try Task.checkCancellation()
            startIndex = QwenImageReferenceLatents.startIndex(
                strength: reference.strength, steps: sigmas.count)
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
            // After the evaluation, so the frame shows the step that has just finished rather
            // than the one about to run, and never on the last: the real decode follows it
            // immediately, and a pooled one in front of that is a second pass through the
            // autoencoder for a picture the caller is a moment from seeing properly.
            //
            // What is decoded is the run's estimate of the *finished* latent, not the latent it
            // is holding. One more Euler step of this prediction, all the way to zero noise, is
            // `x - sigma * v`, and that is what a person means by "how is it coming along". On
            // a four-step ladder the latent itself is still mostly noise until the last rung,
            // and decoding it gives mush.
            if let onPreview, index < sigmas.count - 1 {
                let target = latents
                let prediction = prediction
                let sigmaNext = Float(scheduler.sigmas[index + 1])
                onPreview(index, sigmas.count) {
                    QwenImageLatentPreview.make(
                        tokens: target - prediction * sigmaNext,
                        latentHeight: latentSize.height,
                        latentWidth: latentSize.width, autoencoder: autoencoder)
                }
            }
        }
        return latents
    }
}
