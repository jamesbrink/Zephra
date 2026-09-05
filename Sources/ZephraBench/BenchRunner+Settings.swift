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
        reference: Data?
    ) -> GenerationSettings {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.prompt = options.prompt
        settings.size = ImageSize(width: options.size, height: options.size)
        settings.steps = options.steps
        settings.seed = 42
        settings.referenceImage = reference
        settings.referenceStrength = options.referenceStrength
        return descriptor.capabilities.clamp(settings)
    }
}
