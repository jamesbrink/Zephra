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

    /// One megabyte, as the Performance tab and `@AppStorage` count them.
    static let bytesPerMB = 1 << 20

    /// Limits for this machine: cache at one sixth of RAM capped at 8 GB, total at three quarters.
    static func forThisMachine() -> InferenceTuning {
        let physical = Int(ProcessInfo.processInfo.physicalMemory)
        let gigabyte = 1 << 30
        return InferenceTuning(
            cacheLimitBytes: min(8 * gigabyte, physical / 6),
            memoryLimitBytes: physical / 4 * 3
        )
    }

    /// The cache ceiling this machine recommends, in the megabytes the preference is stored in.
    static var recommendedCacheLimitMB: Int {
        forThisMachine().cacheLimitBytes / bytesPerMB
    }

    /// What a hand-picked cache ceiling is allowed to be. Below 256 MB the allocator thrashes on
    /// a 1024-pixel run; above half the machine's RAM it competes with the weights themselves.
    static var cacheLimitBoundsMB: ClosedRange<Int> {
        let physical = Int(ProcessInfo.processInfo.physicalMemory)
        return 256 ... max(512, physical / 2 / bytesPerMB)
    }

    /// The stored preference as bytes, clamped into the machine's bounds. An unset or absurd
    /// stored value falls back to the recommendation, so a preference can never brick a launch.
    static func storedCacheLimitBytes() -> Int {
        let stored = UserDefaults.standard.object(forKey: AppSettings.cacheLimitMB) as? Int
        let megabytes = stored ?? recommendedCacheLimitMB
        return clampedMB(megabytes) * bytesPerMB
    }

    /// `megabytes` brought inside `cacheLimitBoundsMB`.
    static func clampedMB(_ megabytes: Int) -> Int {
        min(max(megabytes, cacheLimitBoundsMB.lowerBound), cacheLimitBoundsMB.upperBound)
    }
}
