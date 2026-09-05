import QwenImage
import ZephraCore

/// The kit's frame is the shape the engine draws; declared here, since the kit knows nothing
/// of `ZephraCore`.
extension QwenImageLatentPreview: @retroactive PreviewFrame {}
