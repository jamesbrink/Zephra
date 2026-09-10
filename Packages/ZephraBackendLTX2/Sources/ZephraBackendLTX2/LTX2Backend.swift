import Foundation
import LTX2
import ZephraCore
import ZephraMedia
import ZephraMLX

/// Runs LTX-2.5 models through Zephra's own MLX pipeline.
///
/// The instance is deliberately not Sendable: it owns an `LTX2Pipeline`, which holds MLX
/// arrays that must stay on one thread. The engine layer confines it to a serial executor.
///
/// The class is explicitly `nonisolated` so that it compiles the same way whichever target
/// links it. The app builds with default MainActor isolation, and under that setting an
/// inferred-isolated backend could not hand its non-Sendable pipeline to the pipeline's own
/// methods.
public nonisolated final class LTX2Backend: ImageGenerationBackend {
    /// The model family this backend serves.
    public static let backendID = BackendID.ltx2

    /// The descriptor identifier currently in memory, or nil when nothing is loaded.
    public private(set) var loadedModelID: String?

    /// How the loaded weights are held: what the last load did.
    public private(set) var loadedResidency: WeightResidency?

    let pipeline = LTX2Pipeline()
    private var loadedDescriptor: ModelDescriptor?

    /// The switches the composition root read once: the stream's dtype override, the stream
    /// depth and how often a preview frame is made.
    let environment: InferenceEnvironment
    /// The VAE tile the engine set for the run about to start; see `LTX2BackendFactory`. The
    /// video decoder does not tile yet, so the value is read and left alone.
    let tile: VAETileSetting

    /// Creates an idle backend running under `environment`. No weights are touched until
    /// `ensureAvailable` is called.
    public init(environment: InferenceEnvironment, tile: VAETileSetting) {
        self.environment = environment
        self.tile = tile
    }

    /// An idle backend under the default switches, for tests that only ask about the disk.
    public convenience init() {
        self.init(environment: InferenceEnvironment(), tile: VAETileSetting())
    }

    /// Reads the packed weights at `localPath` into memory, held the way `residency` says:
    /// streamed, both 48-layer stacks are read from disk on every pass.
    nonisolated(nonsending) public func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        residency: WeightResidency,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {
        if loadedModelID != nil { unload() }
        let streaming = residency == .streamed ? LTX2Streaming(depth: environment.streamDepth) : nil
        do {
            try pipeline.loadModel(
                at: localPath,
                activation: LTX2ActivationPrecision.resolve(environment: environment),
                streaming: streaming
            ) { progress in
                onProgress(LTX2ProgressMapper.event(from: progress))
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.loadFailed(error.readableMessage)
        }
        loadedModelID = descriptor.id
        loadedDescriptor = descriptor
        loadedResidency = residency
    }

    /// Makes a clip from `settings`: the frames through the pipeline, the MP4 through
    /// `MP4Writer`, and the first frame's PNG as the poster the library indexes.
    nonisolated(nonsending) public func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> GeneratedMedia {
        guard let descriptor = loadedDescriptor else {
            throw BackendError.loadFailed("No model is loaded.")
        }
        // One throttle per run, and no hook at all when frames are switched off, so the loop
        // skips the check; see `PreviewFrameReporter`.
        let onPreview: LTX2Pipeline.PreviewHandler? = PreviewFrameReporter.handler(
            interval: environment.previewInterval, onProgress: onProgress)
        let clip: LTX2Clip
        do {
            clip = try pipeline.generate(
                try LTX2RequestMapper.request(for: settings, descriptor: descriptor, environment: environment),
                onProgress: { progress in onProgress(LTX2ProgressMapper.event(from: progress)) },
                onPreview: onPreview)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.generationFailed(error.readableMessage)
        }
        do {
            let frames = try RGBAFrameSequence(
                width: clip.video.width, height: clip.video.height,
                frameCount: clip.video.frameCount, pixels: clip.video.pixels)
            // The one suspension in a backend's `generate` after its decode: the writer runs on
            // its own queue, so the inference executor is free while the clip is encoded. The
            // store admits nothing else meanwhile; a caller that assumed `generate` never
            // suspends after the decode would be wrong here. Reported as the saving phase, so
            // the interface can say the decode is over and the frames are being written.
            onProgress(GenerationProgressEvent(phase: .saving, fraction: 1))
            let mp4 = try await MP4Writer.encode(frames, frameRate: clip.video.frameRate)
            return .video(
                GeneratedVideo(
                    poster: clip.poster, mp4: mp4, frameCount: clip.video.frameCount,
                    frameRate: clip.video.frameRate))
        } catch {
            throw BackendError.generationFailed(error.readableMessage)
        }
    }

    /// Releases the weights and the scratch memory MLX kept for them.
    public func unload() {
        pipeline.unloadModel()
        loadedModelID = nil
        loadedDescriptor = nil
        loadedResidency = nil
    }
}
