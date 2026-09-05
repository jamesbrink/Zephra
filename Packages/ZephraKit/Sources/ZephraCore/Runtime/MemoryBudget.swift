import Foundation

/// How much memory one generation may occupy on this Mac, and where that number came from.
///
/// The figure that decides whether a model pages is not the RAM in the machine but what the GPU
/// is allowed to keep resident: Metal's recommended working set, which macOS sets at roughly
/// three quarters of RAM and which `sudo sysctl -w iogpu.wired_limit_mb=N` raises. A budget
/// carries both numbers so a picker can say "this Mac's GPU may keep 12.1 GB" and, when raising
/// the limit would change the answer, say so.
public struct MemoryBudget: Hashable, Sendable {
    /// Bytes of RAM in the machine, as `ProcessInfo.physicalMemory` reports them.
    public let physicalMemory: UInt64
    /// Bytes the GPU may keep resident: Metal's `recommendedMaxWorkingSetSize`, or the
    /// fallback fraction of RAM when no GPU has been asked.
    public let gpuWorkingSet: UInt64
    /// `iogpu.wired_limit_mb` as set on this Mac, in megabytes; zero is the macOS default.
    public let wiredLimitMB: Int

    /// The share of RAM assumed for the working set when no GPU has been asked: what the
    /// measured peaks said a Mac survives before Metal's own figure was read, and within a
    /// few percent of it on every Mac measured since.
    public static let fallbackWorkingSetFraction = 0.8

    public init(physicalMemory: UInt64, gpuWorkingSet: UInt64, wiredLimitMB: Int = 0) {
        self.physicalMemory = physicalMemory
        self.gpuWorkingSet = gpuWorkingSet
        self.wiredLimitMB = wiredLimitMB
    }

    /// A budget for a Mac whose GPU has not been asked: tests, and code with no runtime.
    public init(physicalMemory: UInt64) {
        self.init(
            physicalMemory: physicalMemory,
            gpuWorkingSet: UInt64(Double(physicalMemory) * Self.fallbackWorkingSetFraction))
    }

    /// Bytes one generation may occupy before the Mac starts paging.
    public var bytes: Double { Double(gpuWorkingSet) }

    /// Whether the GPU limit was set by hand rather than left to macOS.
    public var isWiredLimitRaised: Bool { wiredLimitMB > 0 }

    /// The highest value the wired limit can sensibly be set to: the whole of RAM, in the
    /// megabytes the sysctl counts in.
    public var physicalMemoryMB: Int { Int(physicalMemory / 1_048_576) }

    /// The command that raises the GPU limit to `megabytes`, for a settings row to show.
    public static func wiredLimitCommand(megabytes: Int) -> String {
        "sudo sysctl -w iogpu.wired_limit_mb=\(megabytes)"
    }
}
