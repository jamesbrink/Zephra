import Synchronization

/// The VAE tile the engine chose for the run about to start, as a slot the runtime handle
/// writes and the backend reads.
///
/// The engine sets the tile through `InferenceRuntime.setVAETileSize` on its own queue as each
/// run starts, and the backend reads it when it builds that run's request, so one slot per
/// family is all the state there is: written from the engine's queue or the settings window,
/// read on the inference queue, under a lock rather than the `nonisolated(unsafe)` static it
/// replaces. A backend factory owns one and hands it to both the runtime handle and every
/// backend it makes.
public final class VAETileSetting: Sendable {
    private let tile = Mutex<Int?>(nil)

    /// A slot with no tile set: the exact, untiled decode.
    public init() {}

    /// The latent tile edge in force, or nil for the exact decode.
    public var value: Int? {
        get { tile.withLock { $0 } }
        set { tile.withLock { $0 = newValue } }
    }
}
