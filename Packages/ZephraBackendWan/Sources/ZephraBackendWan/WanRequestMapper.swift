import Wan
import ZephraCore

/// Translates the engine's settings into the pipeline's request.
enum WanRequestMapper {
    /// The request for `settings` on `descriptor`, after the model's own limits are applied.
    ///
    /// Clamping first is the invariant: the size is aligned to the 32-pixel cell — the
    /// autoencoder's 16 times the transformer's patch of 2 — and the frame count to the
    /// `1 + 4k` ladder, so what the pipeline sees is always something it can run. Steps are
    /// not carried: the distilled schedule fixes them at three. Nor is a strength: a picture is
    /// held as the first frame exactly, which is why the catalog declares none.
    ///
    /// A reference picture is decoded here rather than inside the pipeline, so a picture that
    /// will not open fails before the first denoising step. That is the only thing this throws.
    static func request(
        for settings: GenerationSettings,
        descriptor: ModelDescriptor
    ) throws -> WanGenerationRequest {
        let clamped = descriptor.capabilities.clamp(settings)
        return WanGenerationRequest(
            prompt: clamped.prompt,
            width: clamped.size.width,
            height: clamped.size.height,
            frames: clamped.frames,
            frameRate: descriptor.capabilities.frameRate,
            seed: clamped.seed,
            firstFrame: try clamped.referenceImage.map {
                WanFirstFrame(image: try ReferenceImageDecoding.cgImage(from: $0))
            }
        )
    }

    /// The engine's tile edge, spelled in the eight-pixel cells every picture family shares,
    /// as this autoencoder's sixteen-pixel cells: the same 512 pixels a tile of 64 means
    /// elsewhere is 32 cells here, so a Mac that tiles the pictures tiles the clips at the
    /// same size.
    static func vaeTile(from engineTile: Int?) -> Int? {
        engineTile.map { max(1, $0 * pictureCell / WanLatentLayout.cellScale) }
    }

    /// The latent cell, in pixels, the engine's tile is spelled in.
    private static let pictureCell = 8
}
