import Foundation
import ZephraCore

/// Memory ceilings for the inference runtime, derived from the machine rather than hardcoded.
///
/// The cache limit caps scratch buffers MLX keeps between generations; the memory limit is a
/// soft ceiling on total allocation so a small Mac degrades instead of swapping to death; the
/// wired limit is what MLX keeps resident, so a model that fits the GPU's working set stays in
/// it rather than being paged out from under the next step.
struct InferenceTuning {
    /// Bytes of scratch memory the runtime may retain between generations.
    let cacheLimitBytes: Int
    /// Soft ceiling on total runtime allocation, in bytes.
    let memoryLimitBytes: Int
    /// Bytes MLX may keep wired: the GPU's working set, which `iogpu.wired_limit_mb` raises.
    let wiredLimitBytes: Int

    /// One megabyte, as the Performance tab, `@AppStorage` and `iogpu.wired_limit_mb` count
    /// them: 2^20 bytes, the one definition in this file. `ZephraCore` has no shared unit yet;
    /// when it grows one (`MemoryUnits`, on the roadmap), this and `ZephraBench`'s reading of
    /// the same variable should both take it.
    static let bytesPerMB = 1 << 20

    /// Limits for this machine: cache at one sixth of RAM capped at 8 GB, total and wired at
    /// what the GPU may keep resident. The last two follow `budget` rather than a fraction of
    /// RAM, so a raised `iogpu.wired_limit_mb` is honoured rather than second-guessed.
    /// `wiredLimitOverride` is `InferenceEnvironment.wiredLimitBytes`, `ZEPHRA_WIRED_LIMIT_MB`
    /// read once at the root, for launching the app with that one limit changed.
    static func forThisMachine(
        budget: MemoryBudget, wiredLimitOverride: Int? = nil
    ) -> InferenceTuning {
        let physical = Int(budget.physicalMemory)
        let gigabyte = 1 << 30
        let workingSet = Int(budget.gpuWorkingSet)
        return InferenceTuning(
            cacheLimitBytes: min(8 * gigabyte, physical / 6),
            memoryLimitBytes: workingSet,
            wiredLimitBytes: wiredLimitOverride ?? workingSet
        )
    }

    /// The limits for a Mac whose GPU has not been asked, for the cache recommendation, which
    /// depends on RAM alone.
    static func forThisMachine() -> InferenceTuning {
        forThisMachine(budget: MemoryBudget(physicalMemory: ProcessInfo.processInfo.physicalMemory))
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
