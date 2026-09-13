import Foundation
import ZephraCore

/// `ZEPHRA_GPU_WORKING_SET_MB`, which replays another Mac's GPU budget on this one.
///
/// Everything the app says about what a model costs is drawn from one number — Metal's
/// recommended working set, which `MemoryBudget.gpuWorkingSet` carries: which cards the
/// chooser greys, what the model menu's notes say, whether a load streams
/// (`WeightResidencyPolicy`), whether the decode tiles (`VAETilingPolicy`), what the phone is
/// told, and the static half of the memory guard's answer. A 16 GB Mac therefore sees a
/// different app from a 48 GB one, and the hand checks that matter most are the ones on the
/// small Mac — which is not always a Mac that can be sat in front of. This states the working
/// set the way `ZEPHRA_PREVIEW_STATE` states which pane is up: `physicalMemory` and
/// `wiredLimitMB` stay this Mac's own, so only the figure every policy reads moves, and the
/// live guard, which asks the kernel what is free right now, still reads the real machine.
///
/// Debug only, read once at launch by the composition root and handed down as a value.
enum GPUWorkingSetOverride {
    /// The variable a hand check states the replayed Mac's working set in.
    static let key = "ZEPHRA_GPU_WORKING_SET_MB"

    /// The working set `environment` asks for, in bytes, or nil when it asks for nothing.
    ///
    /// Pure, so a test can drive it. Anything that is not a positive whole number of
    /// mebibytes is nothing at all rather than a guess: a malformed variable must leave the
    /// launch judging by this Mac's own GPU, not by a zero budget that fits no model.
    static func read(_ environment: [String: String]) -> UInt64? {
        #if DEBUG
        guard let raw = environment[key]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
            let megabytes = Int(raw), megabytes > 0
        else { return nil }
        return UInt64(megabytes) * UInt64(MemoryUnits.mebibyte)
        #else
        return nil
        #endif
    }

    /// `budget` with its working set replaced by what `environment` asks for, and untouched
    /// when it asks for nothing.
    static func replacing(_ budget: MemoryBudget, environment: [String: String]) -> MemoryBudget {
        guard let workingSet = read(environment) else { return budget }
        return MemoryBudget(
            physicalMemory: budget.physicalMemory,
            gpuWorkingSet: workingSet,
            wiredLimitMB: budget.wiredLimitMB)
    }
}
