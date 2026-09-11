import Foundation
import MLX
import MLXNN

/// A block's audio lane: the audio stream's own self-attention, text cross-attention and
/// feed-forward with their tables, and the two gated cross-attentions that join the lanes.
///
/// One module beside the video lane's three, nil on a video-only tree, so the pack's flat
/// keys (`audio_attn1`, `scale_shift_table_a2v_ca_video`, ...) sit one level down under
/// `audio.` in the tree and `LTX2TransformerWeights` puts them there. The cross-modal
/// attentions are the audio lane's heads wide on both sides: `audio_to_video_attn` takes the
/// video as queries and the audio as keys and values, `video_to_audio_attn` the other way,
/// and each has a five-row table — scale and shift for each direction, then a gate — that
/// the four `av_ca_*` conditioners on the transformer add their rows to.
final class LTX2AudioLane: Module {
    @ModuleInfo(key: "audio_attn1") var selfAttention: LTX2GatedAttention
    @ModuleInfo(key: "audio_attn2") var crossAttention: LTX2GatedAttention
    @ModuleInfo(key: "audio_ff") var feedForward: LTX2FeedForward
    @ParameterInfo(key: "audio_scale_shift_table") var table: MLXArray
    @ParameterInfo(key: "audio_prompt_scale_shift_table") var promptTable: MLXArray
    @ModuleInfo(key: "audio_to_video_attn") var audioToVideo: LTX2GatedAttention
    @ModuleInfo(key: "video_to_audio_attn") var videoToAudio: LTX2GatedAttention
    @ParameterInfo(key: "scale_shift_table_a2v_ca_video") var crossVideoTable: MLXArray
    @ParameterInfo(key: "scale_shift_table_a2v_ca_audio") var crossAudioTable: MLXArray

    init(_ configuration: LTX2TransformerConfiguration, audio: LTX2AudioConfiguration) {
        let dim = audio.innerDim
        let eps = configuration.normEps
        _selfAttention.wrappedValue = LTX2GatedAttention(
            queryDim: dim, contextDim: dim, heads: audio.heads, headDim: audio.headDim, eps: eps)
        _crossAttention.wrappedValue = LTX2GatedAttention(
            queryDim: dim, contextDim: audio.crossAttentionDim, heads: audio.heads, headDim: audio.headDim, eps: eps)
        _feedForward.wrappedValue = LTX2FeedForward(dim: dim, hidden: audio.feedForwardDim, bias: audio.feedForwardBias)
        _table.wrappedValue = MLXArray.zeros([LTX2TransformerConfiguration.blockModulationRows, dim])
        _promptTable.wrappedValue = MLXArray.zeros([LTX2TransformerConfiguration.promptModulationRows, dim])
        _audioToVideo.wrappedValue = LTX2GatedAttention(
            queryDim: configuration.innerDim, contextDim: dim, heads: audio.heads, headDim: audio.headDim, eps: eps)
        _videoToAudio.wrappedValue = LTX2GatedAttention(
            queryDim: dim, contextDim: configuration.innerDim, heads: audio.heads, headDim: audio.headDim, eps: eps)
        _crossVideoTable.wrappedValue = MLXArray.zeros([LTX2AudioConfiguration.crossModalRows, configuration.innerDim])
        _crossAudioTable.wrappedValue = MLXArray.zeros([LTX2AudioConfiguration.crossModalRows, dim])
    }
}
