import Foundation
import MLX
import MLXRandom

/// The three distilled steps from noise to a latent clip.
extension WanPipeline {
    /// Walks the distilled schedule and returns the finished latent, `[1, 48, F, H, W]`, in the
    /// transformer's normalised space.
    ///
    /// The sample is held in float32 and the transformer sees it in the stream's dtype; the
    /// velocity comes back and the step is taken in float32. The noise for the first latent is
    /// drawn from `seed`, the re-noising at each step from `seed + 10000`, one key split per
    /// step. Cancellation is looked for before each step; a stop that lands during a step is
    /// answered by the streamed transformer between blocks, or by the caller after the decode.
    ///
    /// With a `held` first frame the picture is put in over the sample's first frame before
    /// every forward and after every step, and the held frame's tokens are told timestep 0,
    /// which is how the reference's image-to-video pipeline conditions on one: the model sees
    /// a clean first frame at every step and generates the rest of the clip to follow it.
    func denoise(
        text: MLXArray,
        layout: WanLatentLayout,
        request: WanGenerationRequest,
        held: WanHeldFirstFrame?,
        with loaded: Loaded,
        onProgress: (WanGenerationProgress) -> Void,
        onPreview: PreviewHandler?
    ) throws -> MLXArray {
        let total = schedule.steps
        var sample = MLXRandom.normal(layout.latentShape, key: MLXRandom.key(request.seed))
        let redraws = MLXRandom.split(key: MLXRandom.key(request.seed &+ 10000), into: total)
        for index in 0..<total {
            try Task.checkCancellation()
            onProgress(WanGenerationProgress(stage: .denoising(step: index + 1, of: total)))
            let timestep = WanDistilledSchedule.timesteps[index]
            let input = held?.imposed(on: sample) ?? sample
            let timesteps = held?.timesteps(timestep) ?? MLXArray([Float(timestep)])
            let velocity = try loaded.transformer(
                latent: input.asType(loaded.activation), text: text, timesteps: timesteps
            ).asType(.float32)
            let noise = MLXRandom.normal(sample.shape, key: redraws[index])
            var next = schedule.step(sample: sample, velocity: velocity, index: index, noise: noise)
            if let held { next = held.imposed(on: next) }
            MLX.eval(next)
            if let onPreview, index + 1 < total {
                // The run's estimate of the finished clip, not the sample it is holding.
                let sampled = sample
                let sigma = schedule.sigma(at: index)
                onPreview(index + 1, total) {
                    var estimate = WanDistilledSchedule.denoised(sampled, velocity: velocity, sigma: sigma)
                    if let held { estimate = held.imposed(on: estimate) }
                    // A held run shows the frame *after* the one being held: frame 0 is the
                    // picture that was handed in and would say nothing about the clip.
                    return try WanLatentPreview.make(
                        latent: estimate, decoder: loaded.autoencoder,
                        normalization: loaded.normalization,
                        frame: held == nil ? 0 : Swift.min(1, layout.frames - 1))
                }
            }
            sample = next
        }
        return sample
    }
}
