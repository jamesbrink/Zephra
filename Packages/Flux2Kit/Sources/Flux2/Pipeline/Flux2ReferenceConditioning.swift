import Foundation
import MLX

/// The picture being edited, as the transformer sees it: tokens after the image being made,
/// at their own rows and columns, on their own image index.
///
/// The ordering is the whole of this type. The image being made comes first and the reference
/// after it, and the reference keeps its own grid rather than the output's, with the image
/// index telling the two apart on the rotary embedding's first axis. Swap the order or reuse
/// the index and the model attends to the wrong picture without a shape ever being wrong.
public struct Flux2ReferenceConditioning {
    /// One reference, encoded.
    public struct Reference {
        /// `[1, tokens, 128]`: the packed, normalised latent, flattened row-major.
        public let tokens: MLXArray
        /// One id per token.
        public let ids: [[Int]]
    }

    /// Encodes each picture, `[1, 3, height, width]` in -1 to 1, through the autoencoder.
    public static func encode(
        _ images: [MLXArray], with autoencoder: Flux2Autoencoder
    ) -> [Reference] {
        images.enumerated().map { index, image in
            let packed = autoencoder.encodePacked(image)
            let (height, width) = (packed.dim(2), packed.dim(3))
            return Reference(
                tokens: Flux2LatentPacking.tokens(packed),
                ids: Flux2PositionIDs.image(
                    height: height, width: width,
                    imageIndex: Flux2PositionIDs.referenceImageIndex(index)))
        }
    }

    /// The image being made followed by every reference, with ids to match.
    public static func concatenated(
        target: MLXArray, targetIDs: [[Int]], references: [Reference]
    ) -> (tokens: MLXArray, ids: [[Int]]) {
        guard !references.isEmpty else { return (target, targetIDs) }
        return (
            MLX.concatenated([target] + references.map(\.tokens), axis: 1),
            targetIDs + references.flatMap(\.ids)
        )
    }
}
