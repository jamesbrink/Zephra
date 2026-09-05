import ZephraCore
import ZImage

/// The vendored kit's frame is the shape the engine draws; declared here, since the kit
/// cannot import `ZephraCore`.
extension ZImageLatentPreview: @retroactive PreviewFrame {}
