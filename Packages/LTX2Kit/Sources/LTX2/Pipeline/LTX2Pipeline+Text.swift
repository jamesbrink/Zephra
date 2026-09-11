import Foundation
import MLX

/// From a prompt to the conditioning the transformer attends to.
extension LTX2Pipeline {
    /// The two lanes' conditioning for one prompt: the video connector's output, and the audio
    /// connector's on a variant with the lane.
    struct Conditioning {
        /// `[1, maxTokens, crossAttentionDim]`, in the stream's dtype.
        let video: MLXArray
        /// `[1, maxTokens, audioCrossAttentionDim]`, or nil without the lane.
        let audio: MLXArray?
    }

    /// The connectors' output for `prompt`: tokenised and left-padded, run through every Gemma
    /// layer for all 49 hidden states, projected in float32 by each lane's own extractor, and
    /// passed through each lane's connector, whose registers stand in for the padding so
    /// nothing downstream needs a mask. Gemma runs once; the lanes share its states.
    func encodePrompt(_ prompt: String, maxTokens: Int, with loaded: Loaded) throws -> Conditioning {
        let (ids, mask) = loaded.tokenizer.padded(prompt, to: maxTokens)
        let tokens = MLXArray(ids.map(Int32.init))[.newAxis, 0...]
        let padding = MLXArray(mask.map(Int32.init))[.newAxis, 0...]
        let states = try loaded.textEncoder.hiddenStates(tokens, padding: padding)
        let features = loaded.extractor(states, padding: padding)
        let context = loaded.connector(features.asType(loaded.activation), padding: padding)
        var audio: MLXArray?
        if let lane = loaded.audio {
            let audioFeatures = lane.extractor(states, padding: padding)
            audio = lane.connector(audioFeatures.asType(loaded.activation), padding: padding)
        }
        MLX.eval([context] + (audio.map { [$0] } ?? []))
        return Conditioning(video: context, audio: audio)
    }
}
