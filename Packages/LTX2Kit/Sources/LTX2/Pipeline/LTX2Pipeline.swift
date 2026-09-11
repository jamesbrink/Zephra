import Foundation
import MLX

/// Text to a clip through the four models of LTX-2.5's video path.
///
/// Not Sendable, and confined by its owner to one thread: it holds MLX arrays. The host
/// decides the stream's dtype and whether the two layer stacks are streamed from disk; the kit
/// reads no environment.
public final class LTX2Pipeline {
    /// Everything a loaded model is.
    struct Loaded {
        let tokenizer: LTX2Tokenizer
        let textEncoder: Gemma4TextModel
        let extractor: LTX2FeatureExtractor
        let connector: LTX2TextConnector
        let transformer: LTX2Transformer
        let decoder: LTX2VideoDecoder
        /// The other half of the autoencoder, read only when a first frame is held. 0.64 GB of
        /// bf16 against the model's 19 GB, so it is loaded with everything else rather than on
        /// demand: a module rebuilt when a picture arrives would have to keep its shard mapped
        /// for the pipeline's whole life to have anything to fill itself from.
        let encoder: LTX2VideoEncoder
        /// The spatial latent upsampler a two-stage run doubles its first stage with: 1 GB of
        /// bf16 convolutions, loaded with everything else.
        let upsampler: LTX2LatentUpsampler
        /// The dtype the stream runs in.
        let activation: DType
        /// The audio lane's own pieces, on a variant packed with the lane; nil on a video-only one.
        let audio: LoadedAudio?
    }

    /// What the audio lane needs beyond the transformer: its text path and its way to sound.
    struct LoadedAudio {
        let extractor: LTX2FeatureExtractor
        let connector: LTX2TextConnector
        let decoder: LTX2AudioDecoder
        let vocoder: LTX2Vocoder
    }

    var loaded: Loaded?

    /// The ladder every run's first stage walks; the checkpoint fixes it.
    public let schedule = LTX2DistilledSchedule()
    /// The shorter ladder a two-stage run's second stage walks on the doubled latent.
    public let secondStage = LTX2DistilledSchedule(sigmas: LTX2DistilledSchedule.secondStage)

    public init() {}

    /// Whether a model is in memory.
    public var isLoaded: Bool { loaded != nil }

    /// Called after a step with the step's index, the total, and a closure that makes the
    /// preview frame. A closure rather than a frame so a host that throttles never pays for a
    /// frame it drops.
    public typealias PreviewHandler = (
        _ step: Int, _ totalSteps: Int, _ frame: () -> LTX2LatentPreview
    ) -> Void

    /// Makes the clip `request` asks for.
    public func generate(
        _ request: LTX2GenerationRequest,
        onProgress: (LTX2GenerationProgress) -> Void = { _ in },
        onPreview: PreviewHandler? = nil
    ) throws -> LTX2Clip {
        guard let loaded else { throw LTX2PipelineError.notLoaded }
        let alignment = LTX2LatentLayout.scale
        guard request.width % alignment.width == 0, request.height % alignment.height == 0 else {
            throw LTX2PipelineError.unalignedSize(
                width: request.width, height: request.height, alignment: alignment.width)
        }
        guard request.frames >= 1, (request.frames - 1) % alignment.frames == 0 else {
            throw LTX2PipelineError.unalignedFrames(frames: request.frames, alignment: alignment.frames)
        }
        if let held = request.heldFrames {
            let count = held.images.count
            guard count >= 1, (count - 1) % alignment.frames == 0, count <= request.frames else {
                throw LTX2PipelineError.unalignedHeldFrames(frames: count, alignment: alignment.frames)
            }
        }
        if request.twoStage {
            guard request.width % (2 * alignment.width) == 0, request.height % (2 * alignment.height) == 0 else {
                throw LTX2PipelineError.unalignedSize(
                    width: request.width, height: request.height, alignment: 2 * alignment.width)
            }
        }
        onProgress(LTX2GenerationProgress(stage: .encodingPrompt))
        let text = try encodePrompt(request.prompt, maxTokens: request.maxPromptTokens, with: loaded)
        let latents = request.twoStage
            ? try twoStages(text: text, request: request, with: loaded, onProgress: onProgress, onPreview: onPreview)
            : try oneStage(text: text, request: request, with: loaded, onProgress: onProgress, onPreview: onPreview)
        onProgress(LTX2GenerationProgress(stage: .decoding))
        let video = loaded.decoder.decode(latents.video.asType(loaded.decoder.dtype))
        MLX.eval(video)
        let frames = LTX2Frames.video(video, frameRate: request.frameRate)
        let poster = try LTX2Frames.posterPNG(video)
        var audio: LTX2Audio?
        if let audioLatent = latents.audio, let lane = loaded.audio {
            onProgress(LTX2GenerationProgress(stage: .decodingAudio))
            audio = Self.sound(of: audioLatent, with: lane)
        }
        return LTX2Clip(video: frames, poster: poster, audio: audio)
    }

    /// The finished latents of a run: the video's, and the audio's on a variant with the lane.
    struct Latents {
        let video: MLXArray
        let audio: MLXArray?
    }

    /// A packed audio latent `[1, frames, 128]` decoded to a mel and voiced, as interleaved
    /// stereo samples at 48 kHz.
    static func sound(of latent: MLXArray, with lane: LoadedAudio) -> LTX2Audio {
        let mel = lane.decoder.decode(lane.decoder.unpacked(latent.asType(lane.decoder.dtype)))
        let waveform = lane.vocoder(mel)  // [1, channels, samples]
        let interleaved = waveform.transposed(0, 2, 1).reshaped([-1]).asType(.float32)
        MLX.eval(interleaved)
        return LTX2Audio(
            samples: interleaved.asArray(Float.self), channels: waveform.dim(1),
            sampleRate: LTX2Vocoder.outputSampleRate)
    }
}
