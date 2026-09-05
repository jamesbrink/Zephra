import Synchronization
import ZephraCore

/// What the last streamed pass in the process read and how long it took, for the Performance
/// tab's readout and the benchmark's report.
///
/// A process-wide slot rather than a value threaded up through every family, because the
/// reading is process-wide the way the allocator's are: there is one disk and one stream
/// running at a time. Written by `LayerWeightStream` at the end of a pass on the inference
/// queue; read from anywhere, under a lock.
public enum WeightStreamMeter {
    private static let storage = Mutex<WeightStreamReading?>(nil)

    /// The last pass, or nil while nothing has streamed since launch.
    public static var lastPass: WeightStreamReading? {
        storage.withLock { $0 }
    }

    /// Records a finished pass.
    public static func record(_ reading: WeightStreamReading) {
        storage.withLock { $0 = reading }
    }
}
