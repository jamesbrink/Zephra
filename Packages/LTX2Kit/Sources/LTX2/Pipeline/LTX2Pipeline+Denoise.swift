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
    func denoise(
        text: MLXArray,
        layout: LTX2LatentLayout,
        request: LTX2GenerationRequest,
        with loaded: Loaded,
        onProgress: (LTX2GenerationProgress) -> Void,
        onPreview: PreviewHandler?
    ) throws -> MLXArray {
        let total = schedule.steps
        var sample = layout.pack(MLXRandom.normal(layout.latentShape, key: MLXRandom.key(request.seed)))
        let ancestral = MLXRandom.split(key: MLXRandom.key(request.seed &+ 10000), into: total)
        for index in 0..<total {
            try Task.checkCancellation()
            onProgress(LTX2GenerationProgress(stage: .denoising(step: index + 1, of: total)))
            let sigma = LTX2DistilledSchedule.sigmas[index]
            let velocity = try loaded.transformer(
                tokens: sample.asType(loaded.activation),
                text: text,
                sigma: MLXArray([Float(sigma)]),
                layout: layout,
                frameRate: request.frameRate
            ).asType(.float32)
            let noise = MLXRandom.normal(sample.shape, key: ancestral[index])
            let next = schedule.step(sample: sample, velocity: velocity, index: index, noise: noise)
            MLX.eval(next)
            if let onPreview, index + 1 < total {
                // The run's estimate of the finished clip, not the sample it is holding: the
                // schedule is bent towards its noisy end and the sample decodes to mush until
                // the last rungs. One elementwise operation, inside the closure, so a dropped
                // frame costs nothing.
                onPreview(index + 1, total) {
                    let estimate = LTX2DistilledSchedule.denoised(sample, velocity: velocity, sigma: sigma)
                    return LTX2LatentPreview.make(latent: layout.unpack(estimate), decoder: loaded.decoder)
                }
            }
            sample = next
        }
        return layout.unpack(sample)
    }
}
