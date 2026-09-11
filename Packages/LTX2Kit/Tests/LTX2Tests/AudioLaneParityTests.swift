import Foundation
import MLX
import MLXNN
import Testing
import ZephraMLX

@testable import LTX2

/// The transformer with both lanes, against the reference with the cross-modal attentions on:
/// one block, the whole model at a scalar sigma, and the whole model with a first frame held.
@Suite("the audio lane reproduces the reference's joint forward")
struct AudioLaneParityTests {
    /// The doll's house `dump_transformer.py` builds: the video lane as `TransformerParityTests`
    /// has it, and an audio lane of two heads of eight over eight-channel tokens, reading a
    /// sixteen-wide text stream.
    static let configuration = LTX2TransformerConfiguration(
        inChannels: 8, outChannels: 8, heads: 2, headDim: 16, crossAttentionDim: 32, layers: 2,
        audio: LTX2AudioConfiguration(channels: 8, heads: 2, headDim: 8, crossAttentionDim: 16))
    static let layout = TransformerParityTests.layout
    static let audioLayout = LTX2AudioLatentLayout(frames: 4)

    static func loaded(_ fixture: [String: MLXArray]) throws -> LTX2Transformer {
        let model = LTX2Transformer(configuration)
        try PackedWeightLoading.load(
            into: model,
            weights: LTX2TransformerWeights.sanitized(Fixture.weights(fixture, under: "model."), audio: true),
            manifest: nil)
        return model
    }

    @Test("one block steps both lanes, the cross-modal attentions joining them")
    func block() throws {
        let fixture = try Fixture.load("transformer_audio_block")
        let block = LTX2Block(Self.configuration)
        try PackedWeightLoading.load(
            into: block,
            weights: LTX2TransformerWeights.sanitized(Fixture.weights(fixture, under: "model."), audio: true),
            manifest: nil)
        let model = LTX2Transformer(Self.configuration)
        let head = try #require(model.audioHead)
        let videoPositions = Self.layout.positions(frameRate: 24)
        let audioTimes = LTX2AudioPositions.midpoints(frames: 4, latentsPerSecond: 25)
        let stream = LTX2AudioStream(
            hidden: try #require(fixture["in.audio"]), text: try #require(fixture["in.audio_text"]),
            modulation: try #require(fixture["in.audio_modulation"]), prompt: try #require(fixture["in.audio_prompt"]),
            videoCross: try #require(fixture["in.video_cross"]), videoGate: try #require(fixture["in.video_gate"]),
            audioCross: try #require(fixture["in.audio_cross"]), audioGate: try #require(fixture["in.audio_gate"]),
            rotary: head.rotary.table(positions: audioTimes),
            crossVideoRotary: head.crossRotary.table(positions: videoPositions[0..<1]),
            crossAudioRotary: head.crossRotary.table(positions: audioTimes))
        let conditioning = LTX2BlockConditioning(
            modulation: try #require(fixture["in.modulation"]), prompt: try #require(fixture["in.prompt"]))
        let both = block(
            try #require(fixture["in.hidden"]), text: try #require(fixture["in.text"]),
            conditioning: conditioning, rotary: model.rotary.table(positions: videoPositions),
            textMask: nil, audio: stream)
        #expect(Fixture.maxAbsoluteDifference(both.video, try #require(fixture["out.hidden"])) < 1e-4)
        #expect(Fixture.maxAbsoluteDifference(both.audio, try #require(fixture["out.audio"])) < 1e-4)
    }

    @Test("the audio tokens' seconds and the three rotary tables are the reference's")
    func rotaryTables() throws {
        let fixture = try Fixture.load("transformer_audio_model")
        let head = try #require(LTX2Transformer(Self.configuration).audioHead)
        let times = LTX2AudioPositions.midpoints(frames: 4, latentsPerSecond: 25)
        #expect(Fixture.maxAbsoluteDifference(times, try #require(fixture["rope.audio.midpoints"])) < 1e-6)
        let audio = head.rotary.table(positions: times)
        #expect(Fixture.maxAbsoluteDifference(audio.cos, try #require(fixture["rope.audio.cos"])) < 1e-5)
        #expect(Fixture.maxAbsoluteDifference(audio.sin, try #require(fixture["rope.audio.sin"])) < 1e-5)
        let crossAudio = head.crossRotary.table(positions: times)
        #expect(Fixture.maxAbsoluteDifference(crossAudio.cos, try #require(fixture["rope.cross_audio.cos"])) < 1e-5)
        let crossVideo = head.crossRotary.table(positions: Self.layout.positions(frameRate: 24)[0..<1])
        #expect(Fixture.maxAbsoluteDifference(crossVideo.cos, try #require(fixture["rope.cross_video.cos"])) < 1e-5)
        #expect(Fixture.maxAbsoluteDifference(crossVideo.sin, try #require(fixture["rope.cross_video.sin"])) < 1e-5)
    }

    @Test(
        "the whole model returns both lanes' velocities, at a scalar sigma and with a frame held",
        arguments: [("plain", nil), ("held", Float(1)), ("held_0_6", Float(0.6))] as [(String, Float?)])
    func wholeModel(label: String, strength: Float?) throws {
        let fixture = try Fixture.load("transformer_audio_model")
        let model = try Self.loaded(fixture)
        let prediction = try model.predict(
            tokens: try #require(fixture["in.tokens"]), text: try #require(fixture["in.text"]),
            sigma: try #require(fixture["in.sigma"]), layout: Self.layout, frameRate: 24,
            firstFrameStrength: strength,
            audio: LTX2Transformer.AudioInput(
                tokens: try #require(fixture["in.audio"]), text: try #require(fixture["in.audio_text"]),
                layout: Self.audioLayout))
        let video = try #require(fixture["out.tokens.\(label)"])
        let audio = try #require(fixture["out.audio.\(label)"])
        #expect(prediction.video.shape == video.shape)
        #expect(Fixture.maxAbsoluteDifference(prediction.video, video) < 1e-4, Comment(rawValue: label))
        let predictedAudio = try #require(prediction.audio)
        #expect(predictedAudio.shape == audio.shape)
        #expect(Fixture.maxAbsoluteDifference(predictedAudio, audio) < 1e-4, Comment(rawValue: label))
    }

    @Test("a tree with the lane still answers the video-only fixture with the lane switched off")
    func laneOffIsTheVideoForward() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = LTX2Transformer(Self.configuration)
        // The video-only fixture has no audio weights; the lane stays at its zeros and is never run.
        try model.update(
            parameters: ModuleParameters.unflattened(
                LTX2TransformerWeights.sanitized(Fixture.weights(fixture, under: "model."))),
            verify: [])
        let output = try model(
            tokens: try #require(fixture["in.tokens"]), text: try #require(fixture["in.text"]),
            sigma: try #require(fixture["in.sigma"]), layout: Self.layout, frameRate: 24)
        #expect(Fixture.maxAbsoluteDifference(output, try #require(fixture["out.tokens"])) < 1e-4)
    }

    @Test("the pack's flat audio keys nest under `audio.` in the tree and come back out")
    func keyNesting() {
        #expect(
            LTX2TransformerWeights.moduleName(of: "transformer.transformer_blocks.3.audio_attn1.to_q.weight")
                == "transformer_blocks.3.audio.audio_attn1.to_q.weight")
        #expect(
            LTX2TransformerWeights.moduleName(of: "transformer.transformer_blocks.3.scale_shift_table_a2v_ca_video")
                == "transformer_blocks.3.audio.scale_shift_table_a2v_ca_video")
        #expect(
            LTX2TransformerWeights.moduleName(of: "transformer.av_ca_a2v_gate_adaln_single.emb.timestep_embedder.linear1.weight")
                == "audio.av_ca_a2v_gate_adaln_single.emb.linear1.weight")
        #expect(
            LTX2TransformerWeights.checkpointName(of: "transformer_blocks.3.audio.audio_attn1.to_q.weight")
                == "transformer.transformer_blocks.3.audio_attn1.to_q.weight")
        #expect(
            LTX2TransformerWeights.checkpointName(of: "audio.audio_adaln_single.emb.linear1.weight")
                == "transformer.audio_adaln_single.emb.timestep_embedder.linear1.weight")
        #expect(
            LTX2TransformerWeights.moduleName(of: "transformer.transformer_blocks.3.attn1.to_q.weight")
                == "transformer_blocks.3.attn1.to_q.weight")
    }
}
