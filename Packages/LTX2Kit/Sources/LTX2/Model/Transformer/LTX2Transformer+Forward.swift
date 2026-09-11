import Foundation
import MLX
import MLXFast
import MLXNN

extension LTX2Transformer {
    /// Predicts the velocity for one step.
    ///
    /// - Parameters:
    ///   - tokens: The noisy latent as tokens, `[batch, tokens, inChannels]`, in `layout`'s order.
    ///   - text: The connector's output, `[batch, textTokens, crossAttentionDim]`.
    ///   - sigma: The noise level, `[batch]`, from zero to one; the embedding scales it.
    ///   - layout: The latent's shape, for the rotary positions and the first-frame marker.
    ///   - frameRate: Frames per second of the clip being made; time positions are seconds.
    ///   - firstFrameStrength: How strongly the held latent frames are held, from 0 (not held,
    ///     which is ordinary text-to-video) to 1 (held exactly). Nil is the text-to-video path
    ///     and computes what it always did.
    ///   - heldFrames: How many latent frames are held, from the head: one for a picture held
    ///     as the first frame, `k + 1` for a clip carried on from `1 + 8k` earlier frames.
    ///   - textMask: An additive bias over the text tokens, or nil when every token counts.
    ///
    /// A held frame is a **per-token noise level**, which is how the reference conditions: the
    /// video adaLN and the output head see `sigma * (1 - mask)`, so the tokens carrying the
    /// pictures are told they are that much less noisy than the ones being made, while the
    /// prompt's own adaLN keeps the scalar sigma. Held frames at one strength give that field
    /// exactly two values, so both are computed in one batch of two sigmas and chosen per token
    /// by a marker over the held frames. The keyframe embedding is a different marker: it goes
    /// on the first latent frame alone, the one that encodes a single picture, however many
    /// frames are held (`pipeline_ltx2_condition.py` adds it to latent index 0 and nowhere else).
    ///
    /// The stream runs in the tokens' dtype; the text and the conditioning are cast to it. A
    /// resident run evaluates the stream every `blocksPerEval` blocks; a streamed one is
    /// evaluated block by block by the stream itself, which is also where a stop is answered.
    /// Throws only when streaming: a shard that changed under the model, or a cancellation.
    public func callAsFunction(
        tokens: MLXArray,
        text: MLXArray,
        sigma: MLXArray,
        layout: LTX2LatentLayout,
        frameRate: Double,
        firstFrameStrength: Float? = nil,
        heldFrames: Int = 1,
        textMask: MLXArray? = nil
    ) throws -> MLXArray {
        try predict(
            tokens: tokens, text: text, sigma: sigma, layout: layout, frameRate: frameRate,
            firstFrameStrength: firstFrameStrength, heldFrames: heldFrames, textMask: textMask, audio: nil
        ).video
    }

    /// The audio lane's input to one step: its tokens, its text, and its layout.
    public struct AudioInput {
        public var tokens: MLXArray
        public var text: MLXArray
        public var layout: LTX2AudioLatentLayout

        public init(tokens: MLXArray, text: MLXArray, layout: LTX2AudioLatentLayout) {
            self.tokens = tokens
            self.text = text
            self.layout = layout
        }
    }

    /// Both lanes' velocities for one step, the audio's when `audio` hands the lane a stream
    /// and the tree has one. Without a stream this is the video-only forward exactly.
    public func predict(
        tokens: MLXArray,
        text: MLXArray,
        sigma: MLXArray,
        layout: LTX2LatentLayout,
        frameRate: Double,
        firstFrameStrength: Float? = nil,
        heldFrames: Int = 1,
        textMask: MLXArray? = nil,
        audio: AudioInput?
    ) throws -> LTX2Prediction {
        let positions = layout.positions(frameRate: frameRate)
        let table = rotary.table(positions: positions)
        let keyframe = Self.heldMarker(layout, frames: 1)
        var x = patchify(tokens) + keyframe.asType(tokens.dtype) * keyframeEmbedding.asType(tokens.dtype)
        let held = firstFrameStrength.map { MLX.concatenated([sigma, sigma * (1 - $0)], axis: 0) }
        let marker = heldFrames == 1 ? keyframe : Self.heldMarker(layout, frames: heldFrames)
        let (modulation, embedded) = timestepModulation(held ?? sigma, dtype: x.dtype)
        let (prompt, _) = promptModulation(sigma, dtype: x.dtype)
        let conditioning =
            held == nil
            ? LTX2BlockConditioning(modulation: modulation, prompt: prompt)
            : LTX2BlockConditioning(
                modulation: modulation[0..<1], prompt: prompt,
                conditioned: modulation[1..<2], marker: marker)
        let context = text.asType(x.dtype)

        guard let audio, let audioHead else {
            if let stream {
                try stream.run { block in
                    try Task.checkCancellation()
                    x = block(x, text: context, conditioning: conditioning, rotary: table, textMask: textMask)
                    return [x]
                }
            } else {
                for (index, block) in blocks.enumerated() {
                    x = block(x, text: context, conditioning: conditioning, rotary: table, textMask: textMask)
                    if (index + 1) % blocksPerEval == 0 { MLX.eval(x) }
                }
            }
            return LTX2Prediction(video: head(x, embedded: embedded, marker: held == nil ? nil : marker), audio: nil)
        }
        // The audio lane and the cross-modal conditioners read the scalar sigma, held frame
        // or not; the video's time positions are the first axis of its own, in seconds.
        var (audioStream, audioEmbedded) = audioHead.stream(
            tokens: audio.tokens, text: audio.text, sigma: sigma, audioLayout: audio.layout,
            videoTimes: positions[0..<1], dtype: x.dtype)
        if let stream {
            try stream.run { block in
                try Task.checkCancellation()
                let both = block(x, text: context, conditioning: conditioning, rotary: table, textMask: textMask, audio: audioStream)
                x = both.video
                audioStream.hidden = both.audio
                return [x, audioStream.hidden]
            }
        } else {
            for (index, block) in blocks.enumerated() {
                let both = block(x, text: context, conditioning: conditioning, rotary: table, textMask: textMask, audio: audioStream)
                x = both.video
                audioStream.hidden = both.audio
                if (index + 1) % blocksPerEval == 0 { MLX.eval(x, audioStream.hidden) }
            }
        }
        return LTX2Prediction(
            video: head(x, embedded: embedded, marker: held == nil ? nil : marker),
            audio: audioHead.head(audioStream.hidden, embedded: audioEmbedded))
    }

    /// `[1, tokens, 1]`: true over the first `frames` latent frames' tokens, false elsewhere.
    /// Over one frame it is the keyframe embedding's marker, cast to the stream; over the held
    /// frames it is the per-token modulation's, which selects with it.
    static func heldMarker(_ layout: LTX2LatentLayout, frames: Int) -> MLXArray {
        let marked = layout.frameTokens(frames)
        return MLX.concatenated(
            [
                MLXArray.ones([1, marked, 1], type: Bool.self),
                MLXArray.zeros([1, layout.tokens - marked, 1], type: Bool.self),
            ], axis: 1)
    }

    /// The output head: an affine-free layer norm modulated by the embedded timestep plus the
    /// model's own two-row table (shift first, then scale), then the projection to latents.
    ///
    /// With a `marker` the embedded timestep is a batch of two — the step's sigma and the held
    /// frames', exactly two rows because one strength is what `callAsFunction` concatenates —
    /// and the two rows are chosen per token exactly as a block's nine are. Without a `marker`
    /// `embedded` is the ordinary `[batch, 1, dim]` timestep embedding, batch meaning the
    /// request's own batch of prompts, so it is expanded and passed through whole: picking
    /// batch element 0, as the conditioned path does, would silently drop every generation past
    /// the first in a batch greater than one.
    private func head(_ x: MLXArray, embedded: MLXArray, marker: MLXArray?) -> MLXArray {
        var rows: [MLXArray]
        if let marker {
            rows = LTX2Block.rows(outputTable, Self.embedding(embedded, at: 0), as: x.dtype)
            rows = LTX2Block.blended(
                rows,
                LTX2Block.rows(outputTable, Self.embedding(embedded, at: 1), as: x.dtype),
                marker: marker)
        } else {
            rows = LTX2Block.rows(outputTable, embedded.expandedDimensions(axis: 2), as: x.dtype)
        }
        let normed = MLXFast.layerNorm(x, weight: nil, bias: nil, eps: configuration.normEps)
        return output(normed * (1 + rows[1]) + rows[0])
    }

    /// One batch element of `[batch, 1, dim]` as the `[1, 1, 1, dim]` the row table adds to.
    private static func embedding(_ embedded: MLXArray, at index: Int) -> MLXArray {
        embedded[index..<(index + 1)].expandedDimensions(axis: 2)
    }
}
