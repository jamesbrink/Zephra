import Foundation
import MLX

/// Where each audio token sits in time, in the seconds the rotary embedding was trained on: the
/// midpoint of the mel frames a latent frame covers.
///
/// A latent frame covers four mel frames at a hop of 160 samples of 16 kHz, except the first,
/// which the causal autoencoder makes from one: the reference shifts every bound by `1 - 4`
/// and clamps at zero, so frame 0 spans mel frames `[0, 1)` and frame `f` spans
/// `[4f - 3, 4f + 1)`, each mel frame a hundredth of a second.
public enum LTX2AudioPositions {
    /// Mel frames one latent frame covers.
    static let temporalFactor = 4
    /// The causal offset: the first latent frame holds one mel frame.
    static let causalOffset = 1

    /// The `[1, frames]` positions of every audio token, in seconds.
    public static func midpoints(frames: Int, latentsPerSecond: Double) -> MLXArray {
        let melPerSecond = latentsPerSecond * Double(temporalFactor)
        let times = (0..<frames).map { frame -> Float in
            let start = Double(max(frame * temporalFactor + causalOffset - temporalFactor, 0))
            let end = Double(max((frame + 1) * temporalFactor + causalOffset - temporalFactor, 0))
            return Float((start + end) / 2 / melPerSecond)
        }
        return MLXArray(times)[.newAxis, 0...]
    }
}
