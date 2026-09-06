import Foundation
import MLX

/// Where each video token sits, in the units the rotary embedding was trained on: seconds
/// along time, pixels across height and width, at the midpoint of the latent cell.
///
/// A latent cell covers 32 by 32 pixels and eight frames, except the first, which the causal
/// autoencoder makes from one pixel frame: the reference shifts every frame bound by
/// `1 - 8` and clamps at zero, so cell 0 spans pixel frames `[0, 1)` and cell `t` spans
/// `[8t - 7, 8t + 1)`. The time axis is then divided by the frame rate. Tokens are ordered
/// frame-major, then rows, then columns, which is the order `LTX2LatentLayout` packs them in.
public enum LTX2VideoPositions {
    /// Pixel frames, rows and columns one latent cell covers.
    public static let latentScale = (frames: 8, height: 32, width: 32)
    /// The causal offset: the first latent frame holds one pixel frame.
    static let causalOffset = 1

    /// The `[3, frames * height * width]` positions of every token of a latent that is
    /// `frames` by `height` by `width` cells, for a clip at `frameRate`.
    public static func midpoints(frames: Int, height: Int, width: Int, frameRate: Double) -> MLXArray {
        var times: [Float] = []
        var rows: [Float] = []
        var columns: [Float] = []
        times.reserveCapacity(frames * height * width)
        for frame in 0..<frames {
            let time = Float((frameStart(frame) + frameStart(frame + 1)) / 2 / frameRate)
            for row in 0..<height {
                let y = Float(row * latentScale.height) + Float(latentScale.height) / 2
                for column in 0..<width {
                    times.append(time)
                    rows.append(y)
                    columns.append(Float(column * latentScale.width) + Float(latentScale.width) / 2)
                }
            }
        }
        return MLX.stacked([MLXArray(times), MLXArray(rows), MLXArray(columns)], axis: 0)
    }

    /// The pixel frame a latent cell's time span begins at, after the causal fix.
    static func frameStart(_ cell: Int) -> Double {
        Double(max(cell * latentScale.frames + causalOffset - latentScale.frames, 0))
    }
}
