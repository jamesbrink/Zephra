import Flux2
import ZephraCore

/// The kit's frame is the shape the engine draws; declared here, since the kit knows nothing
/// of `ZephraCore`.
extension Flux2LatentPreview: @retroactive PreviewFrame {}
