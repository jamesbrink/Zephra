import Foundation

/// Memory ceilings for the inference runtime, derived from the machine rather than hardcoded.
///
/// The cache limit caps scratch buffers MLX keeps between generations; the memory limit is a
/// soft ceiling on total allocation so a small Mac degrades instead of swapping to death.
struct InferenceTuning {
    /// Bytes of scratch memory the runtime may retain between generations.
    let cacheLimitBytes: Int
    /// Soft ceiling on total runtime allocation, in bytes.
    let memoryLimitBytes: Int

    /// Limits for this machine: cache at one sixth of RAM capped at 8 GB, total at three quarters.
    static func forThisMachine() -> InferenceTuning {
        let physical = Int(ProcessInfo.processInfo.physicalMemory)
        let gigabyte = 1 << 30
        return InferenceTuning(
            cacheLimitBytes: min(8 * gigabyte, physical / 6),
            memoryLimitBytes: physical / 4 * 3
        )
    }
}
