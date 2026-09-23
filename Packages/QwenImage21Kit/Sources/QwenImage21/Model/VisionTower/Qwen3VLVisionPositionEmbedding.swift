import Foundation
import MLX
import MLXNN

/// How the tower's learned position table is resampled onto one picture's patch grid.
///
/// The table is 2304 rows, which is 48 by 48, and it is **interpolated** rather than sliced:
/// the reference reproduces `F.interpolate(mode: "bilinear", align_corners: true)` as four
/// gather indices and four weights per patch, then sums the gathered rows. A port that took the
/// top-left `rows` by `columns` corner of the table instead would load cleanly and put every
/// reference picture's features in the wrong place.
///
/// `align_corners: true` is what makes the mapping `index * (side - 1) / (size - 1)`: the first
/// and last patch land exactly on the table's first and last row whatever the grid's size. The
/// arithmetic is done in `Float` rather than `Double` on purpose — the reference's is float32,
/// and a source coordinate that is a whole number in one and a hair under it in the other
/// floors to two different rows.
///
/// This is a value rather than a module because the table itself belongs to
/// `Qwen3VLVisionTower`, whose `pos_embed` is a direct child in the checkpoint. A module here
/// would nest that path one level deeper and the weights would need a rename to load.
struct Qwen3VLVisionPositionEmbedding {
    /// Rows along one edge of the square table: 48.
    let side: Int
    /// The tower's spatial merge, which decides the patch order the taps are emitted in.
    let mergeSize: Int

    init(_ configuration: Qwen3VLTextConfiguration.Vision) {
        side = Int(Double(configuration.numPositionEmbeddings).squareRoot().rounded())
        mergeSize = configuration.spatialMergeSize
    }

    /// One position vector per patch of `grid`, `[patches, hidden]`, in the tower's own order.
    func callAsFunction(_ grid: Qwen3VLImageGrid, table: Embedding) -> MLXArray {
        let (indices, weights) = taps(for: grid)
        return (table(indices) * weights.expandedDimensions(axis: -1)).sum(axis: 1)
    }

    /// The four table rows each patch reads and what each is worth: `[patches, 4]` twice.
    func taps(for grid: Qwen3VLImageGrid) -> (indices: MLXArray, weights: MLXArray) {
        var rows: [Int32] = []
        var amounts: [Float] = []
        rows.reserveCapacity(grid.patchCount * 4)
        amounts.reserveCapacity(grid.patchCount * 4)
        for patch in Qwen3VLPatchOrder.frameRepeated(grid, mergeSize: mergeSize) {
            let vertical = axisTaps(index: patch.row, size: grid.rows)
            let horizontal = axisTaps(index: patch.column, size: grid.columns)
            for (verticalTap, verticalWeight) in vertical {
                for (horizontalTap, horizontalWeight) in horizontal {
                    rows.append(Int32(verticalTap * side + horizontalTap))
                    amounts.append(verticalWeight * horizontalWeight)
                }
            }
        }
        let count = rows.count / 4
        return (MLXArray(rows).reshaped(count, 4), MLXArray(amounts).reshaped(count, 4))
    }

    /// The two taps one axis contributes: the source coordinate's floor and the row after it,
    /// clamped to the table's edge, weighted by the linear hat kernel.
    private func axisTaps(index: Int, size: Int) -> [(Int, Float)] {
        let source = (Float(index) * Float(side - 1)) / Float(max(size - 1, 1))
        let floor = source.rounded(.down)
        return (0..<2).map { offset in
            let tap = min(max(Int(floor) + offset, 0), side - 1)
            let distance = abs(source - floor - Float(offset))
            return (tap, max(0, 1 - distance))
        }
    }
}
