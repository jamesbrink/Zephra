import Foundation
import MLX

/// `get_rope_index`: the three position rows a prompt with pictures in it carries.
///
/// A run of text advances all three rows one per token. A picture contributes a `(t, h, w)`
/// mesh over its **merged** grid, with the time row and both spatial rows offset by the
/// position the text had reached, and the text after it resumes at
/// `start + max(rows, columns) / merge` — the longer spatial edge, not the slot count, so a
/// picture costs as many positions as its widest side rather than its area.
///
/// For a prompt with no picture the reference builds `arange(length)` and expands it to three
/// identical rows, which is `Qwen3VLRotary.textPositions` and is why interleaved MRoPE
/// collapses to plain 1-D rope there. This type is only the other case.
public enum Qwen3VLPositionIDs {
    /// The `[3, tokens]` position rows for `layout`, whose image runs line up with `grids`.
    ///
    /// - Parameters:
    ///   - layout: The tokenised prompt, pads already expanded.
    ///   - grids: One patch grid per picture, in the order the runs are.
    ///   - mergeSize: The tower's spatial merge, two.
    public static func positions(
        layout: Qwen3VLTokenLayout, grids: [Qwen3VLImageGrid], mergeSize: Int
    ) -> MLXArray {
        var rows: [[Int32]] = [[], [], []]
        var cursor = 0
        var current = 0
        for (index, run) in layout.imageRuns.enumerated() {
            if run.lowerBound > cursor {
                append(text: run.lowerBound - cursor, from: current, to: &rows)
                current += run.lowerBound - cursor
            }
            let grid = grids[index]
            append(image: grid, mergeSize: mergeSize, from: current, to: &rows)
            current += max(grid.rows, grid.columns) / mergeSize
            cursor = run.upperBound
        }
        if cursor < layout.count {
            append(text: layout.count - cursor, from: current, to: &rows)
        }
        return MLX.stacked(rows.map { MLXArray($0) }, axis: 0)
    }

    private static func append(text length: Int, from start: Int, to rows: inout [[Int32]]) {
        let run = (0..<length).map { Int32(start + $0) }
        for axis in 0..<3 { rows[axis].append(contentsOf: run) }
    }

    /// The reference's `get_vision_position_ids` at `temp_merge_size` 1 and `time_interval` 1:
    /// a `(t, h, w)` mesh in that nesting order, every row offset by `start`.
    private static func append(
        image grid: Qwen3VLImageGrid, mergeSize: Int, from start: Int, to rows: inout [[Int32]]
    ) {
        let height = grid.rows / mergeSize
        let width = grid.columns / mergeSize
        for time in 0..<grid.temporal {
            for row in 0..<height {
                for column in 0..<width {
                    rows[0].append(Int32(time + start))
                    rows[1].append(Int32(row + start))
                    rows[2].append(Int32(column + start))
                }
            }
        }
    }
}
