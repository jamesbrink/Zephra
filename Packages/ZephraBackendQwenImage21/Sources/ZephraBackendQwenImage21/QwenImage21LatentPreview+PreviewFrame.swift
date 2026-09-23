import QwenImage21
import ZephraCore

/// The kit's frame is the shape the engine draws; declared here, since the kit knows nothing
/// of `ZephraCore`.
extension QwenImage21LatentPreview: @retroactive PreviewFrame {}
