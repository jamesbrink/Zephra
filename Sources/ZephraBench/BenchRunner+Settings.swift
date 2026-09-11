import Foundation
import ZephraCore

/// What the warm-up and the timed runs ask the model for.
extension BenchRunner {
    /// A cheap, tiny generation that pays the one-off costs, so the timed runs measure steady
    /// state rather than Metal kernel compilation and first-touch page faults.
    ///
    /// The reference goes into the warm-up too: an edit runs a longer sequence through
    /// different kernel shapes, and warming up without it would leave the first timed run to
    /// pay for their compilation, which is the thing the warm-up exists to prevent.
    static func warmUpSettings(
        _ descriptor: ModelDescriptor,
        prompt: String,
        reference: Data?
    ) -> GenerationSettings {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.prompt = prompt
        settings.size = ImageSize(width: 512, height: 512)
        settings.steps = 1
        // The shortest clip the model makes: the warm-up pays for kernels, not for frames.
        settings.frames = descriptor.capabilities.frameBounds.lowerBound
        settings.seed = 1
        settings.referenceImage = reference
        return descriptor.capabilities.clamp(settings)
    }

    /// The settings every timed run shares. The seed is fixed so repeated invocations produce
    /// the same image and the same amount of work. The result is put through the model's own
    /// limits here rather than only inside the backend, so the report states the size and step
    /// count that actually ran instead of the ones that were asked for — and, on a model that
    /// cannot start from a picture, says so by leaving `--reference` out of the report.
    static func timedSettings(
        _ descriptor: ModelDescriptor,
        options: BenchOptions,
        reference: Data?,
        continuation: ClipContinuation? = nil
    ) -> GenerationSettings {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.prompt = options.prompt
        settings.size = options.size
        settings.steps = options.steps
        if let frames = options.frames { settings.frames = frames }
        settings.seed = 42
        settings.referenceImage = reference
        // A clip carried on is held as the app holds it unless the flag says otherwise; a
        // picture is edited at 0.6, the figure the reports have always been taken at.
        settings.referenceStrength = options.referenceStrength
            ?? (continuation == nil ? 0.6 : descriptor.capabilities.defaultReferenceStrength)
        settings.continuation = continuation
        return descriptor.capabilities.clamp(settings)
    }
}
