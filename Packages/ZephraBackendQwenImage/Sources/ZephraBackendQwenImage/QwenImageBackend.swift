import Foundation
import QwenImage
import ZephraCore
import ZephraSnapshot

/// Runs Qwen-Image family models through the MLX pipeline.
///
/// Not Sendable: it owns a pipeline holding MLX arrays that stay on one thread. The engine layer
/// confines it to a serial executor.
public nonisolated final class QwenImageBackend: ImageGenerationBackend {
    /// The model family this backend serves.
    public static let backendID = BackendID.qwenImage

    /// The descriptor identifier currently in memory, or nil when nothing is loaded.
    public private(set) var loadedModelID: String?

    private let pipeline = QwenImagePipeline()
    private var loadedDescriptor: ModelDescriptor?

    /// Creates an idle backend. No weights are touched until `ensureAvailable` is called.
    public init() {}

    /// Resolves the descriptor's weights, downloading them if they are not on this Mac, and
    /// returns the release `build` packs next.
    ///
    /// Nothing publishes Qwen-Image in a form this loader reads: the release is 57.7 GB of
    /// bfloat16 and the four-step distillation ships apart from it, so what is fetched is both
    /// of those and what is loaded is what the packer makes of them. Three places are looked at
    /// first: the packed variant, which makes the release unnecessary and may even have been
    /// deleted; the folder the user keeps models in; and the hub cache in either layout, read as
    /// a fallback and never written.
    nonisolated(nonsending) public func ensureAvailable(
        _ descriptor: ModelDescriptor,
        locations: ModelLocations,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        switch descriptor.source {
        case .localDirectory:
            let candidates = locations.builtCandidates(for: descriptor)
            if let built = candidates.first(where: {
                LocalSnapshot.qwenImage.missingEntry(in: $0) == nil
            }) {
                return built
            }
            return try LocalSnapshot.qwenImage.verified(
                candidates.first ?? locations.built(descriptor), descriptor: descriptor)
        case .huggingFace:
            if let packed = LocalSnapshot.qwenImage.packedVariant(of: descriptor, in: locations) {
                return packed
            }
            let here = LocalSnapshot.qwenImageRelease.downloadedRelease(of: descriptor, in: locations)
            if let here, locations.missingAdapters(of: descriptor).isEmpty { return here }
            let fetched = try await ModelDownloader().fetch(
                descriptor, into: locations, release: here, onProgress: onProgress)
            return try LocalSnapshot.qwenImageRelease.verified(fetched, descriptor: descriptor)
        }
    }

    /// Reads the weights at `localPath` into memory, releasing whatever was there first.
    nonisolated(nonsending) public func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {
        if loadedModelID != nil { unload() }
        do {
            try pipeline.loadModel(at: localPath) { progress in
                onProgress(QwenImageProgressMapper.event(from: progress))
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.loadFailed(error.readableMessage)
        }
        loadedModelID = descriptor.id
        loadedDescriptor = descriptor
    }

    /// Runs one generation and returns the encoded PNG bytes.
    nonisolated(nonsending) public func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> Data {
        guard let descriptor = loadedDescriptor else {
            throw BackendError.loadFailed("No model is loaded.")
        }
        // One throttle per run, so a frame is made at most every three quarters of a second
        // however fast the steps go by, and none at all when the environment has switched them
        // off. Nil rather than an always-refusing throttle: the loop then skips the check.
        var throttle = PreviewThrottle.environmentInterval.map(PreviewThrottle.init(interval:))
        let onPreview: QwenImagePipeline.PreviewHandler? =
            throttle == nil
            ? nil
            : { step, total, frame in
                guard throttle?.shouldMakeFrame() == true else { return }
                let started = ContinuousClock.now
                let made = frame()
                onProgress(
                    .frame(
                        after: step, of: total,
                        preview: GenerationPreview(
                            width: made.width, height: made.height, pixels: made.pixels,
                            duration: ContinuousClock.now - started)))
            }
        do {
            return try pipeline.generate(
                try QwenImageRequestMapper.request(for: settings, descriptor: descriptor),
                onProgress: { progress in
                    onProgress(QwenImageProgressMapper.event(from: progress))
                },
                onPreview: onPreview
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.generationFailed(error.readableMessage)
        }
    }

    /// Drops the weights and clears the GPU cache, leaving the backend reusable.
    public func unload() {
        pipeline.unloadModel()
        loadedModelID = nil
        loadedDescriptor = nil
    }
}
