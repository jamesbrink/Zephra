import Foundation

/// The order the tower's patches arrive in, which is **block-major** and not raster.
///
/// The processor's patchify permutes a picture to
/// `(blockRow, blockColumn, rowInBlock, columnInBlock)` so that the four patches a two-by-two
/// merge combines are adjacent, which is what lets the merger be a reshape. Three things then
/// have to agree about that order and are all computed here: the patch tensor itself, the
/// learned position table's interpolation taps, and the tower rotary's `(row, column)` pairs.
/// The reference reaches the same order three times over, twice by a reshape-and-transpose and
/// once by this arithmetic (`get_vision_interpolation_indices_and_weights`); one copy here is
/// what keeps them from drifting.
enum Qwen3VLPatchOrder {
    /// The `(row, column)` of every patch of one frame of `grid`, in the order the tower reads
    /// them.
    static func coordinates(of grid: Qwen3VLImageGrid, mergeSize: Int) -> [(row: Int, column: Int)]
    {
        let blocksWide = grid.columns / mergeSize
        let unit = mergeSize * mergeSize
        return (0..<(grid.rows * grid.columns)).map { index in
            let columnInBlock = index % mergeSize
            let rowInBlock = (index / mergeSize) % mergeSize
            let blockColumn = (index / unit) % blocksWide
            let blockRow = index / (unit * blocksWide)
            return (blockRow * mergeSize + rowInBlock, blockColumn * mergeSize + columnInBlock)
        }
    }

    /// The same, repeated for each of the grid's temporal patches, which is what the tower's
    /// position ids and interpolation taps span. A still picture has one.
    static func frameRepeated(
        _ grid: Qwen3VLImageGrid, mergeSize: Int
    ) -> [(row: Int, column: Int)] {
        let frame = coordinates(of: grid, mergeSize: mergeSize)
        guard grid.temporal > 1 else { return frame }
        return (0..<grid.temporal).flatMap { _ in frame }
    }
}
