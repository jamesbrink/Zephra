import Darwin
import Foundation
import ZephraCore

/// What this Mac has free right now, asked of the kernel, beside `GPUMemoryBudget`.
///
/// The budget says what the GPU *may* keep; this says what the machine can actually find this
/// minute, with a browser, a compiler and the model loaded five minutes ago still on it. It is
/// the app's half of `MemoryGuard`: `ZephraCore` and `ZephraEngine` take a `MachineMemoryReader`
/// so their refusals do not depend on what else is running while a suite runs, and this is the
/// one implementation that asks the real host.
///
/// Read fresh on every call rather than once at launch, unlike the budget: RAM does not change
/// while the app runs, but what is going spare changes between one load and the next, which is
/// the whole reason the guard exists.
struct HostMachineMemory: MachineMemoryReader {
    func read() -> MachineMemory? {
        guard let statistics = Self.virtualMemoryStatistics(), let page = Self.pageSize()
        else { return nil }
        let physical = Int64(ProcessInfo.processInfo.physicalMemory)
        // `MachineMemory.availableBytes` states the arithmetic: physical less what is wired,
        // compressed and held internally, with purgeable pages counted back, since the kernel
        // takes those the moment anything asks. Clamped, because the four counts are sampled
        // independently and a heavily loaded Mac can read as owing more than it has.
        let taken = (Int64(statistics.wire_count) + Int64(statistics.compressor_page_count)
            + Int64(statistics.internal_page_count) - Int64(statistics.purgeable_count)) * page
        return MachineMemory(
            physicalBytes: physical,
            availableBytes: min(max(physical - taken, 0), physical))
    }

    /// What one of those counts is worth in bytes, asked of the same host.
    ///
    /// `vm_kernel_page_size` is the figure this is, and it is what `vm_statistics64` counts in,
    /// but it is a global variable the kernel writes before `main` and Swift 6 refuses to read
    /// it from a `Sendable` type. `host_page_size` is the same host answering the same question
    /// through a call, which is 16 KiB on every Mac Zephra runs on.
    private static func pageSize() -> Int64? {
        var size: vm_size_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        guard host_page_size(host, &size) == KERN_SUCCESS, size > 0 else { return nil }
        return Int64(size)
    }

    /// `HOST_VM_INFO64`, or nil where the kernel refused it — a reading nobody has is "do not
    /// know", which the guard treats as leaving the machine half of the question alone.
    private static func virtualMemoryStatistics() -> vm_statistics64_data_t? {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reading in
                host_statistics64(host, HOST_VM_INFO64, reading, &count)
            }
        }
        return result == KERN_SUCCESS ? statistics : nil
    }
}
