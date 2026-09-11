import Foundation
import MLX

/// The audio lane's input to one block: its hidden stream, its text, and the rows every
/// block reads — computed once a step by the transformer's audio head and handed to all
/// forty-eight blocks, as `LTX2BlockConditioning` is for the video lane.
///
/// The audio lane is told the **scalar** sigma throughout, held frame or not, and so are the
/// four cross-modal conditioners (`use_cross_timestep`, which every reference pipeline
/// passes): only the video lane's own rows are per token.
struct LTX2AudioStream {
    /// `[batch, audioTokens, audioDim]`, the lane's stream.
    var hidden: MLXArray
    /// `[batch, textTokens, audioCrossAttentionDim]`, the audio connector's output.
    let text: MLXArray
    /// `[batch, 1, 9, audioDim]`: the lane's shift, scale and gate rows.
    let modulation: MLXArray
    /// `[batch, 1, 2, audioDim]`: shift and scale for the text the lane's cross-attention reads.
    let prompt: MLXArray
    /// `[batch, 1, 4, dim]`: scale and shift the video takes into each cross-modal attention.
    let videoCross: MLXArray
    /// `[batch, 1, 1, dim]`: the gate on what the audio-to-video attention adds to the video.
    let videoGate: MLXArray
    /// `[batch, 1, 4, audioDim]`: scale and shift the audio takes into each cross-modal attention.
    let audioCross: MLXArray
    /// `[batch, 1, 1, audioDim]`: the gate on what the video-to-audio attention adds to the audio.
    let audioGate: MLXArray
    /// The audio tokens' rotary table, for the lane's self-attention.
    let rotary: LTX2RotaryTable
    /// The video tokens on the shared time axis, at the cross-modal attentions' head width.
    let crossVideoRotary: LTX2RotaryTable
    /// The audio tokens on that axis, likewise.
    let crossAudioRotary: LTX2RotaryTable
}
