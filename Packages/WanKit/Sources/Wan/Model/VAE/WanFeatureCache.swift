import Foundation
import MLX

/// What the causal convolutions carry from one chunk of a clip to the next.
///
/// The autoencoder never sees a whole clip: the encoder runs the first frame alone and then
/// four frames at a time, the decoder one latent frame at a time, and each convolution that
/// looks back in time is handed the frames it last saw so the chunk edge is invisible. That is
/// not an optimisation the reference layers over an equivalent one-pass model: the temporal
/// resamplers let the first chunk through without resampling it at all, which is what gives
/// the first frame a latent frame of its own, so the chunking is the model.
///
/// The reference keeps one flat list and walks it in the order its convolutions run, and so
/// does this: every convolution that carries something calls `advance` exactly once per chunk,
/// in a fixed order, and finds the slot it filled last time. `beginChunk` rewinds the walk.
final class WanFeatureCache {
    /// One convolution's carry.
    enum Carry {
        /// Nothing yet: the chunk about to run is the first.
        case nothing
        /// A temporal upsampler that let the first chunk through untouched and has no frames
        /// yet to carry; `"Rep"` in the reference.
        case skipped
        /// The frames the convolution reads in front of its next chunk.
        case frames(MLXArray)
    }

    private var carries: [Carry] = []
    private var cursor = 0

    /// Starts a chunk: the next `advance` reads the first slot.
    func beginChunk() {
        cursor = 0
    }

    /// Hands the next convolution what it carried and stores what it carries on.
    func advance(_ body: (Carry) -> (output: MLXArray, carry: Carry)) -> MLXArray {
        if cursor == carries.count {
            carries.append(.nothing)
        }
        let (output, carry) = body(carries[cursor])
        carries[cursor] = carry
        cursor += 1
        return output
    }

    /// Every array carried, so a finished chunk can be evaluated with them and the graph cut
    /// there rather than growing across the clip.
    var arrays: [MLXArray] {
        carries.compactMap {
            if case .frames(let frames) = $0 { frames } else { nil }
        }
    }
}
