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
/// **Measured on an M4 Max**, a 1024 by 1024 PNG in Release with the weights already loaded and
/// the picture cut into nine tiles: 4x takes 3.75 s and peaks at 2466 MB of MLX allocation; 2x
/// takes 2.80 s and peaks at the same 2466 MB. The peak is identical because it is set by the
/// 4x join, which both do, and the seconds differ only in the PNG encode -- 4096 by 4096 pixels
/// against 2048 by 2048. So 2x is not a cheaper enlargement, it is a 4x enlargement with a
/// smaller file at the end of it, and an interface that implies otherwise would be lying.
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

    /// Enlarges `png` by `request.factor` and hands back a new PNG, transparency and all.
    ///
    /// The network is 4x. A 2x request runs the same pass and then takes the exact 2x2 box mean
    /// of it, which is why the progress a caller sees counts 4x tiles either way.
    ///
    /// **A picture with an alpha channel runs through twice.** The colour goes through as
    /// itself; the alpha goes through as a grey triplet — the same plane in all three channels
    /// — and the mean of what comes back is the new alpha. The network never learned a fourth
    /// channel, but it did learn to enlarge a grey picture, and an alpha plane is one: its
    /// edges are the picture's edges and want the same treatment. The two are recombined as
    /// straight RGBA. That is twice the tiles, which is why the progress counts both lanes.
    public nonisolated(nonsending) func upscale(
        _ png: Data,
        _ request: UpscaleRequest,
        onProgress: @escaping (UpscaleProgressEvent) -> Void
    ) async throws -> Data {
        guard request.factor == 2 || request.factor == 4 else {
            throw UpscaleError.failed("\(request.factor)x is not a size this upscaler makes.")
        }
        let network = try loaded()
        let input = try UpscalePixelBuffer.pixels(from: png)
        let lanes = input.alpha == nil ? 1 : 2
        let perLane = TiledUpscale.tileCount(height: input.rgb.dim(1), width: input.rgb.dim(2))
        let total = perLane * lanes

        var enlarged = try TiledUpscale.run(input.rgb, through: network) { completed, _ in
            onProgress(UpscaleProgressEvent(completedTiles: completed, totalTiles: total))
        }
        var alpha = try input.alpha.map { plane in
            // The plane in all three channels: the network takes three, and a grey picture is
            // what an alpha plane is.
            let grey = MLX.concatenated([plane, plane, plane], axis: -1)
            let run = try TiledUpscale.run(grey, through: network) { completed, _ in
                onProgress(
                    UpscaleProgressEvent(completedTiles: perLane + completed, totalTiles: total))
            }
            return MLX.mean(run, axis: -1, keepDims: true)
        }
        if request.factor == 2 {
            enlarged = BoxDownsample.half(enlarged)
            alpha = alpha.map(BoxDownsample.half)
        }
        MLX.eval(enlarged)
        if let alpha { MLX.eval(alpha) }
        guard !Task.isCancelled else { throw UpscaleError.cancelled }

        let encoded = try UpscalePixelBuffer.png(from: enlarged, alpha)
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
