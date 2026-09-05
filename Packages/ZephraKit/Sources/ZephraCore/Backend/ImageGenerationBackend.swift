import Foundation

/// One inference engine for one family of models. Implementations are NOT Sendable and are
/// confined to a single serial executor owned by the engine layer.
///
/// The async requirements are `nonisolated(nonsending)` so they run on the caller's executor.
/// Without it, an actor that owns a backend cannot call these methods at all: passing an
/// actor-isolated, non-Sendable instance into a `@concurrent` async function is a data race the
/// Swift 6 compiler rejects. Conformances are written as ordinary `async` methods either way.
public protocol ImageGenerationBackend: AnyObject {
    /// The family this implementation serves, matched against a descriptor's backend.
    static var backendID: BackendID { get }

    /// The descriptor identifier currently held in memory, or nil when nothing is loaded.
    var loadedModelID: String? { get }

    /// How the loaded weights are actually held — what `load` did, not what it was asked —
    /// or nil when nothing is loaded or the backend cannot say. A family that cannot stream
    /// answers `.resident` whatever residency it was handed, which is what lets a report say
    /// what ran rather than what was requested.
    var loadedResidency: WeightResidency? { get }

    /// Whether the weights for `descriptor` are already on this Mac, looking in `locations` and
    /// nowhere the user did not ask for. Reads the disk and nothing else: it must never
    /// download, and it must leave whatever is loaded exactly as it was, so a picker can label
    /// every model in the catalog without committing to any of them.
    nonisolated(nonsending) func availability(
        of descriptor: ModelDescriptor,
        locations: ModelLocations
    ) async -> ModelAvailability

    /// Ensures weights are on disk, downloading them into `locations` if needed. Returns the
    /// directory they are in.
    nonisolated(nonsending) func ensureAvailable(
        _ descriptor: ModelDescriptor,
        locations: ModelLocations,
        acquisition: any ModelAcquisition,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL

    /// Loads weights from `localPath` into memory, held the way `residency` says. Progress
    /// handler is intentionally not @Sendable (mirrors the underlying libraries).
    ///
    /// A family that cannot stream is never asked to: `WeightResidencyPolicy` answers
    /// `.resident` for any descriptor whose `streamedPeakBytes` is zero, so such a family may
    /// ignore the argument.
    nonisolated(nonsending) func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        residency: WeightResidency,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws

    /// Returns PNG bytes. Must honour Task cancellation between denoising steps.
    nonisolated(nonsending) func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> Data

    /// Packs whatever `ensureAvailable` left on disk into the form `load` reads, when the two
    /// are not the same thing, and returns the directory to load from. A family whose download
    /// is already loadable, which is most of them, takes the default and does nothing.
    ///
    /// Runs on the inference executor like every other backend call: it is MLX work holding
    /// gigabytes, and a second large allocator elsewhere in the process is not survivable. It
    /// must check cancellation often enough that a person can stop it.
    nonisolated(nonsending) func build(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        locations: ModelLocations,
        onProgress: @escaping @Sendable (BuildProgressEvent) -> Void
    ) async throws -> URL

    /// Releases the loaded weights and any scratch memory.
    func unload()
}

extension ImageGenerationBackend {
    /// A backend that does not say how its weights are held.
    public var loadedResidency: WeightResidency? { nil }

    /// Loads with the weights resident, for the callers that never stream: the benchmark's
    /// default, the quantizer, and the tests.
    public nonisolated(nonsending) func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {
        try await load(descriptor, at: localPath, residency: .resident, onProgress: onProgress)
    }

    /// The download is what gets loaded.
    public nonisolated(nonsending) func build(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        locations: ModelLocations,
        onProgress: @escaping @Sendable (BuildProgressEvent) -> Void
    ) async throws -> URL {
        localPath
    }
}
