import Foundation
import MLX
import MLXRandom

/// The eight ancestral Euler steps from noise to a latent clip.
extension LTX2Pipeline {
    /// Walks the distilled schedule and returns the finished latent, `[1, 128, F, H, W]`.
    ///
    /// The sample is held in float32 and the transformer sees it in the stream's dtype; the
    /// velocity comes back and the step is taken in float32, as the reference does. The noise
    /// for the first latent is drawn from `seed`, the re-noising at each step from `seed +
    /// 10000`, one key split per step, which is the reference's own offset. Cancellation is
    /// looked for before each step; a stop that lands during a step is answered by the streamed
    /// transformer between blocks, or by the caller after the decode.
    ///
    /// With `held` frames the loop starts from the pictures where they are held, tells the
    /// transformer a per-token noise level, and blends the pictures into the finished-latent
    /// estimate each step — all `LTX2FirstFrameConditioning`, which says why in each case. The
    /// schedule itself does not change: the same nine sigmas, and the same scalar sigma at
    /// every conversion and every step.
    ///
    /// `schedule` is the ladder to walk and `start` the packed latent to walk it from — the
    /// noised, doubled latent of a second stage — or nil to start from noise. `steps` is
    /// where this stage's steps sit in the run as a whole, for the progress a two-stage run
    /// reports as one count.
    func denoise(
        text: MLXArray,
        layout: LTX2LatentLayout,
        request: LTX2GenerationRequest,
        held: LTX2HeldLatent?,
        with loaded: Loaded,
        schedule: LTX2DistilledSchedule,
        start: MLXArray? = nil,
        steps: LTX2StepRange? = nil,
        onProgress: (LTX2GenerationProgress) -> Void,
        onPreview: PreviewHandler?
    ) throws -> MLXArray {
        let total = schedule.steps
        let range = steps ?? LTX2StepRange(first: 1, total: total)
        var sample = start ?? layout.pack(MLXRandom.normal(layout.latentShape, key: MLXRandom.key(request.seed)))
        if let held, start == nil {
            sample = LTX2FirstFrameConditioning.initial(
                noise: sample, clean: held.latent, mask: held.mask)
        }
        // The first stage's key is the reference's own offset, so a one-stage clip at a seed
        // is the clip it was; a second stage draws from an offset of its own.
        let ancestral = MLXRandom.split(
            key: MLXRandom.key(request.seed &+ 10000 &+ UInt64(range.first - 1)), into: total)
        for index in 0..<total {
            try Task.checkCancellation()
            onProgress(LTX2GenerationProgress(stage: .denoising(step: range.first + index, of: range.total)))
            let sigma = schedule.sigmas[index]
            let predicted = try loaded.transformer(
                tokens: sample.asType(loaded.activation),
                text: text,
                sigma: MLXArray([Float(sigma)]),
                layout: layout,
                frameRate: request.frameRate,
                firstFrameStrength: held?.strength,
                heldFrames: held?.latentFrames ?? 1
            ).asType(.float32)
            // The picture is blended into the finished-latent estimate and the velocity taken
            // back out of it, both at this step's scalar sigma; the estimate is then the
            // preview's too, so a conditioned run computes it once rather than twice.
            let conditioned = held.map { frame -> (estimate: MLXArray, velocity: MLXArray) in
                let estimate = LTX2FirstFrameConditioning.blended(
                    LTX2DistilledSchedule.denoised(sample, velocity: predicted, sigma: sigma),
                    clean: frame.latent, mask: frame.mask)
                return (
                    estimate,
                    LTX2FirstFrameConditioning.velocity(
                        sample: sample, denoised: estimate, sigma: Float(sigma))
                )
            }
            let estimate = conditioned?.estimate
                ?? LTX2DistilledSchedule.denoised(sample, velocity: predicted, sigma: sigma)
            let noise = MLXRandom.normal(sample.shape, key: ancestral[index])
            var next = schedule.step(sample: sample, denoised: estimate, index: index, noise: noise)
            if let held, held.strength < 1 {
                // A partly held token walks a ladder scaled by what the transformer is told it
                // carries; see `LTX2DistilledSchedule.step(sample:denoised:index:noise:sigmaScale:)`.
                let partial = schedule.step(
                    sample: sample, denoised: estimate, index: index, noise: noise,
                    sigmaScale: Double(1 - held.strength))
                next = MLX.where(held.mask .> 0, partial, next)
            } else if let held {
                next = LTX2FirstFrameConditioning.imposed(next, clean: held.latent, mask: held.mask)
            }
            MLX.eval(next)
            if let onPreview, range.first + index < range.total {
                // The run's estimate of the finished clip, not the sample it is holding: the
                // schedule is bent towards its noisy end and the sample decodes to mush until
                // the last rungs. One elementwise operation, inside the closure for an
                // unconditioned run, so a dropped frame costs nothing.
                let sampled = sample
                onPreview(range.first + index, range.total) {
                    let estimate = conditioned?.estimate
                        ?? LTX2DistilledSchedule.denoised(sampled, velocity: predicted, sigma: sigma)
                    // A held run shows the frame *after* the ones being held: the held frames
                    // are the pictures that were handed in and would say nothing about how the
                    // clip is coming along.
                    return LTX2LatentPreview.make(
                        latent: layout.unpack(estimate), decoder: loaded.decoder,
                        frame: held.map { Swift.min($0.latentFrames, layout.frames - 1) } ?? 0)
                }
            }
            sample = next
        }
        return layout.unpack(sample)
    }
}
