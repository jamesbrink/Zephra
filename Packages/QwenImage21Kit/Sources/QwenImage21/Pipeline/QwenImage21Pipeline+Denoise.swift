import Foundation
import MLX
import MLXRandom
import ZephraMLX

/// The loop of §C.8: noise, walked down the schedule with the condition latents in front of it.
extension QwenImage21Pipeline {
    /// Walks the schedule and hands back the finished latent, `[1, targetTokens, zDim]` in the
    /// transformer's own space.
    func denoise(
        _ request: QwenImage21Request,
        conditioning: QwenImage21Conditioning,
        with model: Loaded,
        onProgress: (QwenImage21GenerationProgress) -> Void,
        onPreview: PreviewHandler? = nil
    ) throws -> MLXArray {
        let target = conditioning.targetTokens
        // The shift counts the picture being made and nothing else, references or not, which
        // is the reference's `calculate_shift(latents.shape[1], ...)` over the target alone.
        let schedule = QwenImage21Schedule(
            configuration: model.configuration.scheduler, steps: request.steps,
            imageSequenceLength: target)
        var latents = try noise(request, conditioning: conditioning, with: model)

        let blocks = model.transformer.layerCount
        let cache = QwenImage21KVCache(layers: blocks)
        let negativeCache = conditioning.negative.map { _ in QwenImage21KVCache(layers: blocks) }

        for (index, timestep) in schedule.timesteps.enumerated() {
            // A stop is answered here and between the transformer's blocks, and it **ends the
            // run** rather than skipping a step — which is what the reference's `interrupt`
            // does too, and for its reason: a skipped step zero never fills the prefix cache,
            // and step one would then decode from an empty one.
            try Task.checkCancellation()
            onProgress(
                QwenImage21GenerationProgress(stage: .denoising(step: index, of: request.steps)))

            let level = MLXArray([Float(timestep / 1000)]).asType(model.activation)
            let input = conditioning.conditionTokens.map {
                MLX.concatenated([$0, latents], axis: 1)
            } ?? latents
            var velocity = try step(
                input, level: level, side: conditioning.positive, cache: cache, index: index,
                target: target, with: model)
            if let negative = conditioning.negative, let negativeCache {
                let unguided = try step(
                    input, level: level, side: negative, cache: negativeCache, index: index,
                    target: target, with: model)
                velocity = unguided + Float(request.guidance) * (velocity - unguided)
            }

            // The reference's `step` upcasts the sample to float32, takes the Euler step there
            // and casts back to the model's dtype. Forty steps of bfloat16 accumulation is a
            // visible drift in the darkest and lightest parts of a picture, and the upcast is
            // one multiply-add a step.
            latents = schedule.step(
                modelOutput: velocity.asType(.float32), index: index,
                sample: latents.asType(.float32)
            ).asType(model.activation)
            MLX.eval(latents)
            preview(
                onPreview, index: index, of: request.steps, latents: latents, velocity: velocity,
                sigma: Float(schedule.sigmas[index + 1]), conditioning: conditioning, with: model)
        }
        return latents
    }

    /// One forward pass, sliced to the picture being made.
    ///
    /// The transformer answers the whole joint sequence on the prefill and only the target's
    /// tokens on a cached step, so the tail slice is the reference's
    /// `noise_pred[:, -latents.size(1):]` and is a no-op past step zero.
    private func step(
        _ input: MLXArray,
        level: MLXArray,
        side: QwenImage21Conditioning.Side,
        cache: QwenImage21KVCache,
        index: Int,
        target: Int,
        with model: Loaded
    ) throws -> MLXArray {
        let velocity = try model.transformer(
            latents: input, text: side.text, timestep: level, layout: side.layout,
            frequencies: side.frequencies, cache: cache, mode: index == 0 ? .extract : .cached)
        return velocity[0..., (velocity.dim(1) - target)...]
    }

    /// What the loop starts from: the request's own noise, or a fresh draw from its seed.
    ///
    /// Drawn in the unpacked latent grid and packed, which is where the reference draws it;
    /// `MLXRandom` is not torch's generator and a picture cannot match one made in `diffusers`
    /// bit for bit, which `PROVENANCE.md` states.
    private func noise(
        _ request: QwenImage21Request,
        conditioning: QwenImage21Conditioning,
        with model: Loaded
    ) throws -> MLXArray {
        let channels = model.configuration.vae.zDim
        let expected = [1, conditioning.targetTokens, channels]
        if let given = request.noise {
            guard given.shape == expected else {
                throw QwenImage21PipelineError.noiseDoesNotMatchLatent(
                    given: given.shape, expected: expected)
            }
            return given.asType(model.activation)
        }
        return QwenImage21LatentPacking.tokens(
            MLXRandom.normal(
                [1, channels, conditioning.latentHeight, conditioning.latentWidth],
                key: MLXRandom.key(request.seed))
        ).asType(model.activation)
    }

    /// Hands the host a way to decode the run's estimate of the **finished** latent.
    ///
    /// After the evaluation, so the frame shows the step that has just finished rather than the
    /// one about to run, and never on the last: the real decode follows it immediately.
    ///
    /// What is offered is `x - sigma * v` and not the latent the loop holds. One more Euler
    /// step of this velocity, all the way to zero noise, is exactly that, and it is what a
    /// person means by "how is it coming along"; the latent itself decodes to mush on a bent
    /// schedule, which 2.1's shifted and stretched ladder is.
    private func preview(
        _ onPreview: PreviewHandler?,
        index: Int,
        of steps: Int,
        latents: MLXArray,
        velocity: MLXArray,
        sigma: Float,
        conditioning: QwenImage21Conditioning,
        with model: Loaded
    ) {
        guard let onPreview, index < steps - 1 else { return }
        let normalization = model.normalization
        let autoencoder = model.autoencoder
        let (height, width) = (conditioning.latentHeight, conditioning.latentWidth)
        onPreview(index, steps) {
            try QwenImage21LatentPreview.make(
                latents: Self.unpacked(latents - velocity * sigma, height: height, width: width),
                normalization: normalization, autoencoder: autoencoder)
        }
    }
}
