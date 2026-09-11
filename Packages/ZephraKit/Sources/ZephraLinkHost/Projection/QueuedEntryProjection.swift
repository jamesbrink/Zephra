import ZephraEngine
import ZephraLinkProtocol

/// The queue and the run in flight as rows.
///
/// Nothing here but the map `QueuedEntry`'s own initializer already does; it is a type of its
/// own so every projection the observation loop publishes is named in one place and the loop
/// reads as a list of them rather than as a mix of calls and initializers.
public enum QueuedEntryProjection {
    /// Everything waiting, in order.
    public static func entries(_ queue: [QueuedGeneration]) -> [QueuedEntry] {
        queue.map(QueuedEntry.init)
    }

    /// What is being rendered, or nothing.
    public static func running(_ entry: QueuedGeneration?) -> QueuedEntry? {
        entry.map(QueuedEntry.init)
    }
}
