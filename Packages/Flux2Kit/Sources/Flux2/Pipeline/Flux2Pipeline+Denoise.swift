import Foundation
import MLX
import MLXRandom

extension Flux2Pipeline {
    /// The reference pictures, encoded, or none.
    func encodeReferences(
        _ request: Flux2GenerationRequest,
        with model: Loaded,
        onProgress: (Flux2GenerationProgress) -> Void
    ) throws -> [Flux2ReferenceConditioning.Reference] {
        guard let data = request.referenceImage else { return [] }
        onProgress(Flux2GenerationProgress(stage: .encodingReference))
        let pixels = try Flux2PixelBuffer.pixels(from: data)
        let references = Flux2ReferenceConditioning.encode(
            [pixels], with: model.autoencoder, dtype: Flux2TransformerPrecision.activation)
        MLX.eval(references.map(\.tokens))
        return references
    }

    /// The loop: noise, walked down the schedule, then decoded.
    func denoise(
        _ request: Flux2GenerationRequest,
        text: MLXArray,
        references: [Flux2ReferenceConditioning.Reference],
        with model: Loaded,
        onProgress: (Flux2GenerationProgress) -> Void,
        onPreview: PreviewHandler? = nil
    ) throws -> Data {
        let configuration = model.configuration
        let packedHeight = request.height / Self.sizeAlignment
        let packedWidth = request.width / Self.sizeAlignment
        let targetTokens = packedHeight * packedWidth

        // Noise is drawn in the packed space the transformer reads, as the reference draws it;
        // the schedule's shift counts only the image being made, references or not.
        let scheduler = FlowMatchEulerScheduler(
            configuration: configuration.scheduler, steps: request.steps,
            imageSequenceLength: targetTokens)
        let dtype = Flux2TransformerPrecision.activation
        var latents = Flux2LatentPacking.tokens(
            MLXRandom.normal(
                [1, configuration.vae.packedChannels, packedHeight, packedWidth],
                key: MLXRandom.key(request.seed))
        ).asType(dtype)
        let text = text.asType(dtype)

        let textLength = text.dim(1)
        let targetIDs = Flux2PositionIDs.image(height: packedHeight, width: packedWidth)
        let (_, imageIDs) = Flux2ReferenceConditioning.concatenated(
            target: latents, targetIDs: targetIDs, references: references)
        let frequencies = Flux2RotaryEmbedding(
            theta: configuration.transformer.ropeTheta,
            axesDim: configuration.transformer.axesDimsRope
        ).frequencies(ids: Flux2PositionIDs.text(count: textLength) + imageIDs)

        for (index, sigma) in scheduler.timesteps.enumerated() {
            try Task.checkCancellation()
            onProgress(Flux2GenerationProgress(stage: .denoising(step: index, of: request.steps)))
            let (input, _) = Flux2ReferenceConditioning.concatenated(
                target: latents, targetIDs: targetIDs, references: references)
            let velocity = model.transformer(
                latents: input, text: text,
                timestep: MLXArray([Float(sigma)]),
                frequencies: frequencies, textLength: textLength
            )[0..., 0..<targetTokens]
            latents = scheduler.step(modelOutput: velocity, index: index, sample: latents)
            MLX.eval(latents)
            // After the evaluation, so the frame shows the step that has just finished rather
            // than the one about to run, and never on the last: the real decode follows it
            // immediately, and a pooled one in front of that is a pass through the autoencoder
            // for a picture the caller is a second from seeing properly.
            //
            // What is decoded is the run's estimate of the *finished* latent, not the latent it
            // is holding. One more Euler step of this velocity, all the way to zero noise, is
            // `x - sigma * v`, and that is what a person means by "how is it coming along". The
            // latent itself is no good here: klein's four-step ladder is bent so far towards
            // the noisy end that the third rung is still at sigma 0.77 at 1024 pixels, and
            // decoding it gives flat brown mush every time.
            if let onPreview, index < scheduler.timesteps.count - 1 {
                let target = latents
                let velocity = velocity
                let sigmaNext = Float(scheduler.sigmas[index + 1])
                let autoencoder = model.autoencoder
                onPreview(index, request.steps) {
                    Flux2LatentPreview.make(
                        tokens: target - velocity * sigmaNext,
                        packedHeight: packedHeight, packedWidth: packedWidth,
                        autoencoder: autoencoder)
                }
            }
        }

        onProgress(Flux2GenerationProgress(stage: .decoding))
        let grid = Flux2LatentPacking.grid(latents, height: packedHeight, width: packedWidth)
        let pixels = model.autoencoder.decodePacked(grid)
        MLX.eval(pixels)
        return try Flux2PixelBuffer.png(from: pixels)
    }
}
