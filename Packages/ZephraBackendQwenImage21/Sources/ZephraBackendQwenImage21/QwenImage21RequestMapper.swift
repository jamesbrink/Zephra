import Foundation
import QwenImage21
import ZephraCore

/// Translates the engine's settings into the pipeline's request.
enum QwenImage21RequestMapper {
    /// The request for `settings` on `descriptor`, after the model's own limits are applied.
    ///
    /// Clamping first is the invariant: the size is aligned to the 32-pixel grid the pipeline
    /// refuses anything else on, the steps are bounded, and a reference picture is dropped for
    /// a model that cannot read one. So what the pipeline sees is always something it can run.
    ///
    /// The bytes cross as bytes. `QwenImage21Request.references` is `[Data]` and the kit's own
    /// `QwenImage21ReferencePicture` decodes, fits and composites each one inside the pipeline,
    /// where the size it is brought to is decided — so a decode here would be a resample the
    /// pipeline immediately redoes, and the four channels 2.1's autoencoder reads would have to
    /// survive a second trip through Core Graphics to get there.
    ///
    /// The negative prompt rides only above guidance 1, which is where the reference's
    /// `true_cfg_scale > 1 and negative_prompt is not None` runs the second forward; 2.1 is
    /// meant to be sampled without guidance, and a negative prompt under it would be a string
    /// the loop reads and never uses.
    static func request(
        for settings: GenerationSettings,
        descriptor: ModelDescriptor
    ) -> QwenImage21Request {
        let clamped = descriptor.capabilities.clamp(settings)
        return QwenImage21Request(
            prompt: clamped.prompt,
            negativePrompt: clamped.guidance > 1 ? (clamped.negativePrompt ?? "") : "",
            width: clamped.size.width,
            height: clamped.size.height,
            steps: clamped.steps,
            guidance: clamped.guidance,
            seed: clamped.seed,
            // One line, and the one line a multi-reference `GenerationSettings` changes: when
            // Core grows `referenceImages: [ReferencePicture]` this becomes that array mapped
            // to its bytes. The model card allows ten; the engine offers one today.
            references: [clamped.referenceImage].compactMap { $0 }
        )
    }

    /// The engine's tile edge, spelled in the eight-pixel cells every picture family shares, as
    /// this autoencoder's sixteen-pixel cells: the same 512 pixels a tile of 64 means elsewhere
    /// is 32 cells here, so a Mac that tiles klein's pictures tiles 2.1's at the same size.
    /// Nil — the exact, untiled decode — when the engine is not tiling at all.
    ///
    /// Floored at twelve cells, which is measured rather than chosen: the tiled decode's
    /// overlap approximation is coarse below about twelve, and a tile of eight came back at
    /// 17 dB against the untiled decode. A Mac too small for a twelve-cell tile is a Mac the
    /// memory guard refuses the model on, not one this quietly gives a blurred picture to.
    static func vaeTile(from engineTile: Int?) -> Int? {
        engineTile.map { max(minimumTile, $0 * pictureCell / latentCell) }
    }

    /// The latent cell, in pixels, the engine's tile is spelled in.
    private static let pictureCell = 8
    /// This autoencoder's own latent cell, in pixels.
    private static let latentCell = 16
    /// The smallest tile whose overlap approximation is still faithful. See `PROVENANCE.md`.
    private static let minimumTile = 12
}
