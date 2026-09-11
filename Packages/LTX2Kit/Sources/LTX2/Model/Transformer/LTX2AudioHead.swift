import Foundation
import MLX
import MLXFast
import MLXNN

/// The audio lane's ends and its conditioning: the patchify in, the output head, the lane's
/// two adaLN-single heads, and the four cross-modal conditioners every block's a2v and v2a
/// attentions read.
///
/// One module under `audio.` on the transformer, nil on a video-only tree, holding the pack's
/// `audio_patchify_proj`, `audio_adaln_single`, `audio_prompt_adaln_single`, `audio_proj_out`,
/// `audio_scale_shift_table` and the four `av_ca_*_adaln_single` heads. The rotary embeddings
/// are the lane's: one over the audio tokens' seconds for its self-attention, and one at the
/// cross-modal attentions' width serving both the video's and the audio's time positions.
final class LTX2AudioHead: Module {
    @ModuleInfo(key: "audio_patchify_proj") var patchify: Linear
    @ModuleInfo(key: "audio_adaln_single") var timestepModulation: LTX2AdaLayerNormSingle
    @ModuleInfo(key: "audio_prompt_adaln_single") var promptModulation: LTX2AdaLayerNormSingle
    @ModuleInfo(key: "av_ca_video_scale_shift_adaln_single") var videoCross: LTX2AdaLayerNormSingle
    @ModuleInfo(key: "av_ca_a2v_gate_adaln_single") var videoGate: LTX2AdaLayerNormSingle
    @ModuleInfo(key: "av_ca_audio_scale_shift_adaln_single") var audioCross: LTX2AdaLayerNormSingle
    @ModuleInfo(key: "av_ca_v2a_gate_adaln_single") var audioGate: LTX2AdaLayerNormSingle
    @ModuleInfo(key: "audio_proj_out") var output: Linear
    /// Shift and scale for the output head, `[2, audioDim]`, added to the embedded timestep.
    @ParameterInfo(key: "audio_scale_shift_table") var outputTable: MLXArray

    let configuration: LTX2AudioConfiguration
    /// The rotary embedding over the audio tokens' time, for the lane's self-attention.
    let rotary: LTX2RotaryEmbedding
    /// The rotary embedding at the cross-modal attentions' width, over either lane's time.
    let crossRotary: LTX2RotaryEmbedding
    private let eps: Float

    init(_ configuration: LTX2TransformerConfiguration, audio: LTX2AudioConfiguration) {
        self.configuration = audio
        eps = configuration.normEps
        let dim = audio.innerDim
        let scale = configuration.timestepScale
        rotary = LTX2RotaryEmbedding(
            heads: audio.heads, headDim: audio.headDim, maxPositions: [audio.ropeMaxSeconds],
            theta: configuration.ropeTheta)
        crossRotary = LTX2RotaryEmbedding(
            heads: audio.heads, headDim: audio.crossAttentionDim / audio.heads,
            maxPositions: [audio.ropeMaxSeconds], theta: configuration.ropeTheta)
        _patchify.wrappedValue = Linear(audio.channels, dim, bias: true)
        _timestepModulation.wrappedValue = LTX2AdaLayerNormSingle(
            dim: dim, rows: LTX2TransformerConfiguration.blockModulationRows, timestepScale: scale)
        _promptModulation.wrappedValue = LTX2AdaLayerNormSingle(
            dim: dim, rows: LTX2TransformerConfiguration.promptModulationRows, timestepScale: scale)
        _videoCross.wrappedValue = LTX2AdaLayerNormSingle(dim: configuration.innerDim, rows: 4, timestepScale: scale)
        _videoGate.wrappedValue = LTX2AdaLayerNormSingle(dim: configuration.innerDim, rows: 1, timestepScale: scale)
        _audioCross.wrappedValue = LTX2AdaLayerNormSingle(dim: dim, rows: 4, timestepScale: scale)
        _audioGate.wrappedValue = LTX2AdaLayerNormSingle(dim: dim, rows: 1, timestepScale: scale)
        _output.wrappedValue = Linear(dim, audio.channels, bias: true)
        _outputTable.wrappedValue = MLXArray.zeros([2, dim])
    }

    /// The lane's stream for one step: the tokens patchified and every row computed at the
    /// scalar `sigma`, with the three rotary tables over `audioLayout`'s and the video's time.
    /// Returns the stream and the embedded timestep the output head reads.
    func stream(
        tokens: MLXArray, text: MLXArray, sigma: MLXArray, audioLayout: LTX2AudioLatentLayout,
        videoTimes: MLXArray, dtype: DType
    ) -> (stream: LTX2AudioStream, embedded: MLXArray) {
        let (modulation, embedded) = timestepModulation(sigma, dtype: dtype)
        let audioTimes = LTX2AudioPositions.midpoints(
            frames: audioLayout.frames, latentsPerSecond: configuration.latentsPerSecond)
        let stream = LTX2AudioStream(
            hidden: patchify(tokens.asType(dtype)),
            text: text.asType(dtype),
            modulation: modulation,
            prompt: promptModulation(sigma, dtype: dtype).modulation,
            videoCross: videoCross(sigma, dtype: dtype).modulation,
            videoGate: videoGate(sigma, dtype: dtype).modulation,
            audioCross: audioCross(sigma, dtype: dtype).modulation,
            audioGate: audioGate(sigma, dtype: dtype).modulation,
            rotary: rotary.table(positions: audioTimes),
            crossVideoRotary: crossRotary.table(positions: videoTimes),
            crossAudioRotary: crossRotary.table(positions: audioTimes))
        return (stream, embedded)
    }

    /// The output head: an affine-free layer norm modulated by the embedded timestep plus the
    /// two-row table (shift first, then scale), then the projection back to latent channels.
    func head(_ x: MLXArray, embedded: MLXArray) -> MLXArray {
        let rows = LTX2Block.rows(outputTable, embedded.expandedDimensions(axis: 2), as: x.dtype)
        let normed = MLXFast.layerNorm(x, weight: nil, bias: nil, eps: eps)
        return output(normed * (1 + rows[1]) + rows[0])
    }
}
