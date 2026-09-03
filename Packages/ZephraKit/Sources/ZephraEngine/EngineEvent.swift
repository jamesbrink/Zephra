import ZephraCore

/// One thing the backend said while it was working, on its way from the inference queue to the
/// main actor. Every case carries a value type so nothing owned by the backend escapes its queue.
public enum EngineEvent: Sendable {
    /// Bytes are moving from the network onto disk.
    case download(DownloadProgressEvent)
    /// A downloaded release is being packed into the variant this Mac loads.
    case build(BuildProgressEvent)
    /// Compute is happening, either loading weights or running a generation.
    case progress(GenerationProgressEvent)
    /// An upscale has finished another tile. Its own case rather than a phase of `.progress`:
    /// an upscale has no denoising steps to count and no model behind it.
    case upscale(UpscaleProgressEvent)
}
