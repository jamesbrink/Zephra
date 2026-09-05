import SwiftUI
import ZephraCore

/// How the composition root hands the machine's memory budget down to the views that word the
/// model picker and the Performance tab.
///
/// Read once at launch from the GPU and the `iogpu.wired_limit_mb` sysctl, then constant: RAM
/// does not change while the app runs, and Metal reports the working set per device query. A
/// view that never had one gets the GPU-less fallback, which is what previews see.
extension EnvironmentValues {
    @Entry var memoryBudget = MemoryBudget(physicalMemory: ProcessInfo.processInfo.physicalMemory)
}
