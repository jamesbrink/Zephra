import Foundation
import MLX
import ZephraMLX

/// The finished latent turned back into a picture: §C.11, in order.
extension QwenImage21Pipeline {
    /// Unpacks, denormalises, decodes and encodes the result as a PNG, RGBA only where the
    /// picture has transparency.
    func decode(
        _ request: QwenImage21Request,
        latents: MLXArray,
        with model: Loaded,
        onProgress: (QwenImage21GenerationProgress) -> Void
    ) throws -> QwenImage21Result {
        onProgress(QwenImage21GenerationProgress(stage: .decoding))
        let grid = Self.unpacked(
            latents,
            height: request.height / model.latentScale,
            width: request.width / model.latentScale)
        let pixels = model.autoencoder.decode(
            model.normalization.denormalize(grid), tile: tile(request, with: model))
        MLX.eval(pixels)
        // Four channels where the picture has transparency, so `PixelBuffer` writes
        // `CGImageAlphaInfo.last` and the fourth channel is the picture's own straight alpha;
        // three where it does not, so an ordinary picture is an ordinary opaque file
        // (`QwenImage21Opacity`).
        return QwenImage21Result(
            png: try PixelBuffer.png(from: QwenImage21Opacity.flattened(pixels)),
            width: request.width, height: request.height, latents: latents)
    }

    /// `[1, tokens, zDim]` in the transformer's packed space back to the channels-last latent
    /// grid the autoencoder reads, `[1, height, width, zDim]`.
    ///
    /// Two turns in a row, and both are load-bearing: `QwenImage21LatentPacking` speaks the
    /// reference's channels-first grid, and 2.1's autoencoder — like every MLX one here —
    /// speaks channels-last. Getting either wrong scrambles the picture into plausible noise
    /// rather than failing.
    static func unpacked(_ tokens: MLXArray, height: Int, width: Int) -> MLXArray {
        QwenImage21LatentPacking.grid(tokens, height: height, width: width)
            .transposed(0, 2, 3, 1)
    }

    /// The tile the decode runs in, or nil for the exact one pass. A preview frame's decode
    /// takes the same answer, so a frame never peaks higher than the picture will.
    ///
    /// A tile at or above the latent's own long edge **is** the untiled decode, so it is
    /// answered as nil rather than sent round `TiledDecode` for one tile. Below that the
    /// approximation is real: measured against the untiled decode of a 16 x 16 latent, twelve
    /// cells is 24 dB and eight is 17, because this decoder's four nearest-neighbour doublings
    /// each followed by a 3 x 3 convolution reach further into the picture than the quarter-tile
    /// overlap cross-fades. `PROVENANCE.md` carries the curve; a host picking a tile should
    /// pick well up it.
    func tile(_ request: QwenImage21Request, with model: Loaded) -> Int? {
        guard let tile = request.vaeTile else { return nil }
        let long = max(request.height, request.width) / model.latentScale
        return tile < long ? tile : nil
    }
}
