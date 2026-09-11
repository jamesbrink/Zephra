import Foundation
import MLX
import MLXNN

/// The block with both lanes: the reference's `LTX2VideoTransformerBlock.forward` with the
/// cross-modal attentions on.
///
/// In order: the video's self-attention, then the audio's; the video's text cross-attention,
/// then the audio's; both lanes normalised once more, the audio-to-video attention added to
/// the video and the video-to-audio attention added to the audio, each through its own scale,
/// shift and gate from the lane's five-row table plus the transformer's conditioners; then
/// each lane's feed-forward. The video arithmetic is the same as the audio-free block's, with
/// the cross-modal term between the text cross-attention and the feed-forward.
extension LTX2Block {
    /// Both lanes stepped. The video's `conditioning` is per token when a frame is held; the
    /// audio's rows and the cross-modal rows are the scalar sigma's.
    func callAsFunction(
        _ hidden: MLXArray,
        text: MLXArray,
        conditioning: LTX2BlockConditioning,
        rotary: LTX2RotaryTable,
        textMask: MLXArray?,
        audio stream: LTX2AudioStream
    ) -> (video: MLXArray, audio: MLXArray) {
        guard let lane = audio else { preconditionFailure("a video-only block was handed an audio stream") }
        let rows = Self.rows(table, conditioning, as: hidden.dtype)
        let promptRows = Self.rows(promptTable, conditioning.prompt, as: hidden.dtype)
        let audioRows = Self.rows(lane.table, stream.modulation, as: hidden.dtype)
        let audioPromptRows = Self.rows(lane.promptTable, stream.prompt, as: hidden.dtype)
        var x = hidden
        var a = stream.hidden.asType(hidden.dtype)

        var normed = LTX2RMSNorm.normalize(x, eps: eps) * (1 + rows[1]) + rows[0]
        x = x + selfAttention(normed, rotary: rotary) * rows[2]
        var normedAudio = LTX2RMSNorm.normalize(a, eps: eps) * (1 + audioRows[1]) + audioRows[0]
        a = a + lane.selfAttention(normedAudio, rotary: stream.rotary) * audioRows[2]

        normed = LTX2RMSNorm.normalize(x, eps: eps) * (1 + rows[7]) + rows[6]
        let context = text.asType(x.dtype) * (1 + promptRows[1]) + promptRows[0]
        x = x + crossAttention(normed, context: context, mask: textMask) * rows[8]
        normedAudio = LTX2RMSNorm.normalize(a, eps: eps) * (1 + audioRows[7]) + audioRows[6]
        let audioContext = stream.text.asType(a.dtype) * (1 + audioPromptRows[1]) + audioPromptRows[0]
        a = a + lane.crossAttention(normedAudio, context: audioContext, mask: textMask) * audioRows[8]

        // The cross-modal rows: scale then shift for a2v, scale then shift for v2a, in that
        // order, and the gate on its own row; both norms taken before either attention.
        let videoCross = Self.rows(lane.crossVideoTable[0..<4], stream.videoCross, as: x.dtype)
        let videoGate = Self.rows(lane.crossVideoTable[4..<5], stream.videoGate, as: x.dtype)[0]
        let audioCross = Self.rows(lane.crossAudioTable[0..<4], stream.audioCross, as: a.dtype)
        let audioGate = Self.rows(lane.crossAudioTable[4..<5], stream.audioGate, as: a.dtype)[0]
        let normedVideo = LTX2RMSNorm.normalize(x, eps: eps)
        normedAudio = LTX2RMSNorm.normalize(a, eps: eps)
        let videoForA2V = normedVideo * (1 + videoCross[0]) + videoCross[1]
        let audioForA2V = normedAudio * (1 + audioCross[0]) + audioCross[1]
        x = x + videoGate * lane.audioToVideo(
            videoForA2V, context: audioForA2V, rotary: stream.crossVideoRotary, keyRotary: stream.crossAudioRotary)
        let videoForV2A = normedVideo * (1 + videoCross[2]) + videoCross[3]
        let audioForV2A = normedAudio * (1 + audioCross[2]) + audioCross[3]
        a = a + audioGate * lane.videoToAudio(
            audioForV2A, context: videoForV2A, rotary: stream.crossAudioRotary, keyRotary: stream.crossVideoRotary)

        normed = LTX2RMSNorm.normalize(x, eps: eps) * (1 + rows[4]) + rows[3]
        x = x + feedForward(normed) * rows[5]
        normedAudio = LTX2RMSNorm.normalize(a, eps: eps) * (1 + audioRows[4]) + audioRows[3]
        a = a + lane.feedForward(normedAudio) * audioRows[5]
        return (x, a)
    }
}
