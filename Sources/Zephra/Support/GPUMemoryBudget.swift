import Darwin
import Foundation
import ZephraCore

/// What this Mac's GPU may keep resident, read once at launch.
///
/// Two readings make the budget: Metal's recommended working set, through the runtime, and
/// the `iogpu.wired_limit_mb` sysctl, which is what a person raises to let the GPU have more
/// of RAM than macOS allows by default. The sysctl is read only to say whether it was set;
/// the working set already reflects it. Both are read at launch, because Metal reports the
/// working set per device query and a running app does not ask twice.
enum GPUMemoryBudget {
    /// The sysctl a person raises to give the GPU more of RAM.
    static let wiredLimitKey = "iogpu.wired_limit_mb"

    /// The budget for this Mac, from the runtime when there is one and from RAM alone when
    /// there is not — a preview build or a SwiftUI preview.
    static func forThisMachine(runtime: (any InferenceRuntime)?) -> MemoryBudget {
        let physical = ProcessInfo.processInfo.physicalMemory
        guard let workingSet = runtime?.gpuWorkingSetBytes(), workingSet > 0 else {
            return MemoryBudget(physicalMemory: physical)
        }
        return MemoryBudget(
            physicalMemory: physical,
            gpuWorkingSet: workingSet,
            wiredLimitMB: wiredLimitMB()
        )
    }

    /// `iogpu.wired_limit_mb` as it stands, or 0 when it is unset or cannot be read.
    static func wiredLimitMB() -> Int {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(wiredLimitKey, &value, &size, nil, 0) == 0 else { return 0 }
        return Int(value)
    }
}
