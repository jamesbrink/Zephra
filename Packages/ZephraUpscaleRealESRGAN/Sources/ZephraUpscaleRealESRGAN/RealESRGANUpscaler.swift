import Foundation
import MLX
import ZephraCore

/// Real-ESRGAN's `realesr-general-x4v3` behind the engine's upscaler seam.
///
/// A post-process, not a backend: 1.2 million parameters and 2.4 MB of bundled float16, so it
/// loads in well under a second and holds nothing worth unloading between presses. It runs on
/// the engine's serial inference executor, the same queue a generation runs on, so a Metal job
/// here never overlaps one there.
///
/// Compute is float32. The weights are 4.9 MB at float32, so a narrower dtype buys nothing on
/// the model and only halves the activations, and the switch — one `asType` at load and one on
/// the input — stays cheap to make later because the tiler, the shuffle, and the box mean are
/// all dtype-agnostic.
///
/// **Measured on an M4 Max**, a 1024 by 1024 PNG in Release, weights already loaded: a 4x pass
/// takes MEASURED_TIME_4X and peaks at MEASURED_PEAK_4X; the 2x pass is the same run plus the
/// box mean, MEASURED_TIME_2X and MEASURED_PEAK_2X. So 2x is not the cheaper choice, and an
/// interface that implies it is would be lying.
public final class RealESRGANUpscaler: ImageUpscaler {
    /// The network, once something has asked for it. Nil until then and after `unload()`.
    private var network: SRVGGNet?

    /// The one symbol a composition root needs in order to wire the upscaler into the engine.
    ///
    /// A factory rather than an instance for the reason `BackendFactory` is one: upscalers are
    /// not Sendable, so the engine builds the one it owns inside its own isolation.
    public static func make() -> any ImageUpscaler { RealESRGANUpscaler() }

    /// Makes an upscaler that has not read its weights yet.
    public init() {}

    /// Enlarges `png` by `request.factor` and hands back a new opaque PNG.
    ///
    /// The network is 4x. A 2x request runs the same pass and then takes the exact 2x2 box mean
    /// of it, which is why the progress a caller sees counts 4x tiles either way.
    public nonisolated(nonsending) func upscale(
        _ png: Data,
        _ request: UpscaleRequest,
        onProgress: @escaping (UpscaleProgressEvent) -> Void
    ) async throws -> Data {
        guard request.factor == 2 || request.factor == 4 else {
            throw UpscaleError.failed("\(request.factor)x is not a size this upscaler makes.")
        }
        let network = try loaded()
        let pixels = try UpscalePixelBuffer.pixels(from: png)
        let total = TiledUpscale.tileCount(height: pixels.dim(1), width: pixels.dim(2))

        var enlarged = try TiledUpscale.run(pixels, through: network) { completed, count in
            onProgress(UpscaleProgressEvent(completedTiles: completed, totalTiles: count))
        }
        if request.factor == 2 {
            enlarged = BoxDownsample.half(enlarged)
        }
        MLX.eval(enlarged)
        guard !Task.isCancelled else { throw UpscaleError.cancelled }

        let encoded = try UpscalePixelBuffer.png(from: enlarged)
        // The last tile's report comes from inside the tiler, before the join, the downsample,
        // and the encode. A caller drawing a progress bar should see it reach the end, so the
        // finished run says so itself.
        onProgress(UpscaleProgressEvent(completedTiles: total, totalTiles: total))
        return encoded
    }

    /// Releases the weights and hands MLX's scratch back.
    public func unload() {
        network = nil
        Memory.clearCache()
    }

    /// The network, read from the bundle the first time it is asked for.
    private func loaded() throws -> SRVGGNet {
        if let network { return network }
        let built = SRVGGNet(.generalX4v3)
        let checkpoint = try BundledWeights.located()
        let published: [String: MLXArray]
        do {
            published = try MLX.loadArrays(url: checkpoint)
        } catch {
            throw UpscaleError.weightsMissing("\(checkpoint.lastPathComponent): \(error)")
        }
        // Float16 on disk, float32 in the stream: the file is small enough that its dtype is
        // about download size rather than about arithmetic, and MLX takes a convolution's
        // output dtype from its weights.
        let sanitized = SRVGGNetWeights.sanitized(published)
            .mapValues { $0.asType(.float32) }
        try SRVGGNetWeights.load(into: built, weights: sanitized)
        MLX.eval(built)
        network = built
        return built
    }
}
