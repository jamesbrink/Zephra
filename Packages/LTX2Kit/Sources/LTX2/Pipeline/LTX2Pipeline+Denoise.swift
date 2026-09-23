import Foundation
import MLX
import MLXRandom

/// The eight ancestral Euler steps from noise to a latent clip.
extension LTX2Pipeline {
    /// Walks the distilled schedule and returns the finished latents, the video's
    /// `[1, 128, F, H, W]` and, on a variant with the audio lane, the audio's `[1, L, 128]`.
    ///
    /// The sample is held in float32 and the transformer sees it in the stream's dtype; the
    /// velocity comes back and the step is taken in float32, as the reference does. The noise
    /// for the first latent is drawn from `seed`, the re-noising at each step from `seed +
    /// 10000`, one key split per step, which is the reference's own offset; the audio's first
    /// latent from `seed + 30000` and its re-noising from `seed + 50000`, keys of this port's
    /// own, since the reference draws both lanes from one generator in turn and no port can
    /// reproduce that draw. Cancellation is looked for before each step; a stop that lands
    /// during a step is answered by the streamed transformer between blocks, or by the caller
    /// after the decode.
    ///
    /// With `held` frames the loop starts from the pictures where they are held, tells the
    /// transformer a per-token noise level, and blends the pictures into the finished-latent
    /// estimate each step — all `LTX2FirstFrameConditioning`, which says why in each case. The
    /// audio is never held: it is told the scalar sigma and stepped as it is, which is what
    /// the reference does beside a held frame. The schedule itself does not change: the same
    /// nine sigmas, and the same scalar sigma at every conversion and every step.
    ///
    /// `schedule` is the ladder to walk and `start` the packed latent to walk it from — the
    /// noised, doubled latent of a second stage, with `audioStart` its audio — or nil to start
    /// from noise. `steps` is where this stage's steps sit in the run as a whole, for the
    /// progress a two-stage run reports as one count.
    func denoise(
        text: Conditioning,
        layout: LTX2LatentLayout,
        request: LTX2GenerationRequest,
        held: LTX2HeldLatent?,
        with loaded: Loaded,
        schedule: LTX2DistilledSchedule,
        start: MLXArray? = nil,
        audioStart: MLXArray? = nil,
        steps: LTX2StepRange? = nil,
        onProgress: (LTX2GenerationProgress) -> Void,
        onPreview: PreviewHandler?
    ) throws -> Latents {
        let total = schedule.steps
        let range = steps ?? LTX2StepRange(first: 1, total: total)
        var sample = start ?? layout.pack(MLXRandom.normal(layout.latentShape, key: MLXRandom.key(request.seed)))
        if let held, start == nil {
            sample = LTX2FirstFrameConditioning.initial(
                noise: sample, clean: held.latent, mask: held.mask)
        }
        let audioLayout = LTX2AudioLatentLayout(pixelFrames: request.frames, frameRate: request.frameRate)
        var audio: MLXArray? = text.audio.map { _ in
            audioStart ?? MLXRandom.normal(audioLayout.shape, key: MLXRandom.key(request.seed &+ 30000))
        }
        // The first stage's key is the reference's own offset, so a one-stage clip at a seed
        // is the clip it was; a second stage draws from an offset of its own.
        let ancestral = MLXRandom.split(
            key: MLXRandom.key(request.seed &+ 10000 &+ UInt64(range.first - 1)), into: total)
        let audioAncestral = MLXRandom.split(
            key: MLXRandom.key(request.seed &+ 50000 &+ UInt64(range.first - 1)), into: total)
        for index in 0..<total {
            try Task.checkCancellation()
            onProgress(LTX2GenerationProgress(stage: .denoising(step: range.first + index, of: range.total)))
            let sigma = schedule.sigmas[index]
            let prediction = try loaded.transformer.predict(
                tokens: sample.asType(loaded.activation),
                text: text.video,
                sigma: MLXArray([Float(sigma)]),
                layout: layout,
                frameRate: request.frameRate,
                firstFrameStrength: held?.strength,
                heldFrames: held?.latentFrames ?? 1,
                audio: Self.audioInput(audio, text: text.audio, layout: audioLayout, activation: loaded.activation))
            let predicted = prediction.video.asType(.float32)
            // The picture is blended into the finished-latent estimate and the velocity taken
            // back out of it, both at this step's scalar sigma; the estimate is then the
            // preview's too, so a conditioned run computes it once rather than twice.
            let estimate = held.map { frame in
                LTX2FirstFrameConditioning.blended(
                    LTX2DistilledSchedule.denoised(sample, velocity: predicted, sigma: sigma),
                    clean: frame.latent, mask: frame.mask)
            } ?? LTX2DistilledSchedule.denoised(sample, velocity: predicted, sigma: sigma)
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
            if let current = audio, let velocity = prediction.audio {
                audio = schedule.step(
                    sample: current, velocity: velocity.asType(.float32), index: index,
                    noise: MLXRandom.normal(current.shape, key: audioAncestral[index]))
            }
            MLX.eval([next] + (audio.map { [$0] } ?? []))
            if let onPreview, range.first + index < range.total {
                // The run's estimate of the finished clip, not the sample it is holding: the
                // schedule is bent towards its noisy end and the sample decodes to mush until
                // the last rungs. One elementwise operation, inside the closure for an
                // unconditioned run, so a dropped frame costs nothing.
                onPreview(range.first + index, range.total) {
                    // A held run shows the frame *after* the ones being held: the held frames
                    // are the pictures that were handed in and would say nothing about how the
                    // clip is coming along.
                    try LTX2LatentPreview.make(
                        latent: layout.unpack(estimate), decoder: loaded.decoder,
                        frame: held.map { Swift.min($0.latentFrames, layout.frames - 1) } ?? 0)
                }
            }
            sample = next
        }
        return Latents(video: layout.unpack(sample), audio: audio)
    }

    /// The audio lane's input for one step, or nil when the run has no audio.
    private static func audioInput(
        _ tokens: MLXArray?, text: MLXArray?, layout: LTX2AudioLatentLayout, activation: DType
    ) -> LTX2Transformer.AudioInput? {
        guard let tokens, let text else { return nil }
        return LTX2Transformer.AudioInput(tokens: tokens.asType(activation), text: text, layout: layout)
    }
}
