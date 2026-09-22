import Foundation

/// A reference picture's patch grid: `image_grid_thw`, the one number the tower, the prompt's
/// token count and the decoder's positions all read.
///
/// A still picture is one temporal patch, and the tower's preprocessing repeats it to fill
/// `temporal_patch_size`, so `temporal` is 1 for everything this kit encodes. `rows` and
/// `columns` are the picture's pixels over `patch_size`, which is 16 — and the **slots** it
/// becomes in the prompt are those over the two-by-two spatial merge, so a 1024-square
/// reference is a 64 by 64 patch grid and 1024 image slots. The latent grid the transformer
/// works on is `(height / 16, width / 16)`, four times as many cells, which is where the
/// four-latents-per-slot rule in the joint sequence comes from.
public struct Qwen3VLImageGrid: Hashable, Sendable {
    /// Temporal patches. One for a still picture.
    public let temporal: Int
    /// Patch rows: pixel height over `patch_size`.
    public let rows: Int
    /// Patch columns: pixel width over `patch_size`.
    public let columns: Int

    public init(temporal: Int = 1, rows: Int, columns: Int) {
        self.temporal = temporal
        self.rows = rows
        self.columns = columns
    }

    /// Patches the tower reads: `t * h * w`.
    public var patchCount: Int { temporal * rows * columns }

    /// Image slots this picture becomes in the prompt: the patches over the merge squared.
    public func slotCount(mergeSize: Int) -> Int { patchCount / (mergeSize * mergeSize) }

    /// `[t, h, w]`, the order the reference's `image_grid_thw` row carries.
    public var thw: [Int] { [temporal, rows, columns] }
}
