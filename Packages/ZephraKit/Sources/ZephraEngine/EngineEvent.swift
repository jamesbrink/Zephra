import ZephraCore

/// One thing the backend said while it was working, on its way from the inference queue to the
/// main actor. Both cases carry a value type so nothing owned by the backend escapes its queue.
public enum EngineEvent: Sendable {
    /// Bytes are moving from the network onto disk.
    case download(DownloadProgressEvent)
    /// Compute is happening, either loading weights or running a generation.
    case progress(GenerationProgressEvent)
}
