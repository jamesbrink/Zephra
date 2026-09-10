import Foundation
import MLX
import MLXRandom

/// One stage, or two: the eight-step ladder at the clip's size, or that ladder at half the
/// size followed by the doubled latent's three-step refinement.
extension LTX2Pipeline {
    /// The finished latent for a one-stage run, `[1, 128, F, H, W]`.
    func oneStage(
        text: MLXArray, request: LTX2GenerationRequest, with loaded: Loaded,
        onProgress: (LTX2GenerationProgress) -> Void, onPreview: PreviewHandler?
    ) throws -> MLXArray {
        let layout = LTX2LatentLayout(
            pixelFrames: request.frames, pixelWidth: request.width, pixelHeight: request.height)
        let held = try request.firstFrame.map {
            try LTX2HeldFirstFrame($0, layout: layout, encoder: loaded.encoder)
        }
        return try denoise(
            text: text, layout: layout, request: request, held: held, with: loaded,
            schedule: schedule, onProgress: onProgress, onPreview: onPreview)
    }

    /// The finished latent for a two-stage run: the first ladder at half the size, the latent
    /// doubled by the spatial upsampler, noised to the second ladder's top and walked down it.
    ///
    /// The reference's two-stage distilled pipeline: stage one composes the clip on a quarter
    /// of the tokens, and stage two spends three steps on the detail the upsampler cannot
    /// invent, which is most of the quality of a one-stage run at the full size for about
    /// three fifths of its step cost. A held first frame is encoded twice, once at each size,
    /// so both stages hold the picture at their own resolution, and the doubled, noised latent
    /// enters the second stage with the picture blended in by its strength exactly as noise
    /// enters the first. The eleven steps are reported as one count.
    func twoStages(
        text: MLXArray, request: LTX2GenerationRequest, with loaded: Loaded,
        onProgress: (LTX2GenerationProgress) -> Void, onPreview: PreviewHandler?
    ) throws -> MLXArray {
        let total = schedule.steps + secondStage.steps
        let half = LTX2LatentLayout(
            pixelFrames: request.frames, pixelWidth: request.width / 2, pixelHeight: request.height / 2)
        let full = LTX2LatentLayout(
            pixelFrames: request.frames, pixelWidth: request.width, pixelHeight: request.height)
        let heldHalf = try request.firstFrame.map {
            try LTX2HeldFirstFrame($0, layout: half, encoder: loaded.encoder)
        }
        let coarse = try denoise(
            text: text, layout: half, request: request, held: heldHalf, with: loaded,
            schedule: schedule, steps: LTX2StepRange(first: 1, total: total),
            onProgress: onProgress, onPreview: onPreview)
        try Task.checkCancellation()
        let doubled = loaded.upsampler.upsample(coarse, statistics: loaded.decoder.statistics)
        let noise = MLXRandom.normal(full.latentShape, key: MLXRandom.key(request.seed &+ 20000))
        var start = full.pack(secondStage.noised(doubled, noise: noise))
        let heldFull = try request.firstFrame.map {
            try LTX2HeldFirstFrame($0, layout: full, encoder: loaded.encoder)
        }
        if let heldFull {
            // The same entry the first stage makes from noise: the picture blended in by its
            // strength, so a partly held frame is partly held here too and a fully held one
            // is the picture exactly.
            start = LTX2FirstFrameConditioning.initial(noise: start, clean: heldFull.latent, mask: heldFull.mask)
        }
        MLX.eval(start)
        return try denoise(
            text: text, layout: full, request: request, held: heldFull, with: loaded,
            schedule: secondStage, start: start,
            steps: LTX2StepRange(first: schedule.steps + 1, total: total),
            onProgress: onProgress, onPreview: onPreview)
    }
}
