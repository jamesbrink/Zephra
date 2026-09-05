import Foundation
import MLX

/// The picture being edited, as the transformer sees it: tokens after the image being made,
/// at their own rows and columns, on their own image index.
///
/// The ordering is the whole of this type, and the dtype is the rest of it. The image being
/// made comes first and the reference after it, and the reference keeps its own grid rather
/// than the output's, with the image index telling the two apart on the rotary embedding's
/// first axis. Swap the order or reuse the index and the model attends to the wrong picture
/// without a shape ever being wrong. And the reference's tokens are cast to the stream's
/// dtype as they are encoded: the autoencoder answers in float32, MLX promotes when the two
/// are concatenated, and a float32 reference beside a bfloat16 target silently ran every
/// edit's whole transformer in float32.
public struct Flux2ReferenceConditioning {
    /// One reference, encoded.
    public struct Reference {
        /// `[1, tokens, 128]`: the packed, normalised latent, flattened row-major.
        public let tokens: MLXArray
        /// One id per token.
        public let ids: [[Int]]
    }

    /// Encodes each picture, `[1, 3, height, width]` in -1 to 1, through the autoencoder,
    /// with the tokens in `dtype` — the stream's, `Flux2TransformerPrecision.activation`.
    public static func encode(
        _ images: [MLXArray], with autoencoder: Flux2Autoencoder, dtype: DType
    ) -> [Reference] {
        images.enumerated().map { index, image in
            let packed = autoencoder.encodePacked(image)
            let (height, width) = (packed.dim(2), packed.dim(3))
            return Reference(
                tokens: Flux2LatentPacking.tokens(packed).asType(dtype),
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
