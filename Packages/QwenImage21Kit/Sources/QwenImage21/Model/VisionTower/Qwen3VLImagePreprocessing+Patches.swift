import Foundation
import MLX

extension Qwen3VLImagePreprocessing {
    /// The tower's input for one picture: `[patches, channels * frames * patch²]` and the grid
    /// that says what shape those patches were in.
    ///
    /// - Parameters:
    ///   - image: `[height, width, 3]` over 0 to 255, alpha already flattened over white.
    ///   - processor: The published `preprocessor_config.json`, for the patch and merge sizes,
    ///     the rescale and the mean and deviation — all 0.5, so the range becomes -1 to 1.
    ///
    /// - Throws: `Qwen3VLEncodingError.sizeNotFitted` when either edge is not a multiple of
    ///   `patch_size * merge_size`. The pipeline's own fit guarantees it; a caller that skipped
    ///   the fit would otherwise get a silently cropped picture, since the reshape below drops
    ///   any remainder.
    public static func patches(
        of image: MLXArray, processor: QwenImage21ProcessorConfiguration
    ) throws -> (patches: MLXArray, grid: Qwen3VLImageGrid) {
        let (height, width) = (image.dim(0), image.dim(1))
        let factor = processor.patchSize * processor.mergeSize
        guard height % factor == 0, width % factor == 0 else {
            throw Qwen3VLEncodingError.sizeNotFitted(height: height, width: width, factor: factor)
        }

        let mean = MLXArray(processor.imageMean.map { Float($0) })
        let deviation = MLXArray(processor.imageStd.map { Float($0) })
        let normalised =
            (image.asType(.float32) * Float(processor.rescaleFactor) - mean) / deviation

        let grid = Qwen3VLImageGrid(
            rows: height / processor.patchSize, columns: width / processor.patchSize)
        let (patch, merge) = (processor.patchSize, processor.mergeSize)
        let channels = image.dim(2)

        // (channel, blockRow, rowInBlock, rowInPatch, blockColumn, columnInBlock, columnInPatch)
        // permuted to (blockRow, blockColumn, rowInBlock, columnInBlock, channel, row, column),
        // which is the reference's `permute(0, 2, 5, 3, 6, 1, 4, 7)` without its batch axis.
        var laid = normalised.transposed(2, 0, 1)
            .reshaped(channels, grid.rows / merge, merge, patch, grid.columns / merge, merge, patch)
            .transposed(1, 4, 2, 5, 0, 3, 6)

        // The frame axis goes between the channel and the patch's rows, which is where the
        // Conv3d's `[out, 3, 2, 16, 16]` kernel keeps it. A still picture fills both frames
        // with itself, and a broadcast is what the reference's `.expand` is too.
        let frames = processor.temporalPatchSize
        laid = MLX.broadcast(
            laid.expandedDimensions(axis: 5),
            to: [grid.rows / merge, grid.columns / merge, merge, merge, channels, frames, patch, patch])

        return (laid.reshaped(grid.patchCount, channels * frames * patch * patch), grid)
    }
}
