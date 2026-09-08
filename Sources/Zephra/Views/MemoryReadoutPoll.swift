import Foundation
import ZephraCore

/// The readings `MemoryReadout` shows, and the loop that takes them.
///
/// Split out of the view because the view was holding four stored properties and the rule is
/// three; the readings are what a reading is *of*, so they are what leaves.
///
/// The loop lives exactly as long as the `.task` that started it, which on macOS is exactly as
/// long as the Performance tab is the selected one. That is worth writing down because it is
/// not obvious and it is what the readout's scope rests on: a `TabView` here builds only the
/// selected tab's content, sends `onDisappear` and cancels its `.task` when the selection
/// moves, and starts it again when it comes back — measured on macOS 15, where an unselected
/// tab's views are out of the window altogether. So a hidden Performance tab reads nothing,
/// and neither does a closed Settings window.
@MainActor @Observable
final class MemoryReadoutPoll {
    /// What the allocator held at the last reading, or nil before the first one.
    private(set) var snapshot: MemorySnapshot?
    /// What the last streamed pass read and how fast, or nil while nothing has streamed.
    private(set) var streamed: WeightStreamReading?

    /// Reads the runtime once a second until the task is cancelled. A build with no runtime to
    /// ask returns at once and leaves `snapshot` nil, which is what the readout says so.
    func run(reading runtime: InferenceRuntime?) async {
        guard let runtime else { return }
        while !Task.isCancelled {
            snapshot = runtime.memorySnapshot()
            streamed = runtime.weightStreamReading()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
