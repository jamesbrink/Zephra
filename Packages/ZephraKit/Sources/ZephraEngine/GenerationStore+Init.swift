import Foundation
import ZephraCore

extension GenerationStore {
    /// Creates a store for one model, running on the backends `registry` knows how to build.
    /// `outputDirectory` nil means ~/Pictures/Zephra. `runtime` is the GPU runtime the decode's
    /// tile is set on before each run; nil for a test or a tool, which then sets none.
    public convenience init(
        descriptor: ModelDescriptor = ModelCatalog.default,
        registry: BackendRegistry,
        outputDirectory: URL? = nil,
        locations: ModelLocations = .default,
        upscaler: UpscalerFactory? = nil, downloads: ModelDownloads = ModelDownloads(),
        runtime: (any InferenceRuntime)? = nil
    ) {
        self.init(
            descriptor: descriptor, registry: registry, output: outputDirectory,
            locations: locations, upscaler: upscaler, downloads: downloads, runtime: runtime)
    }
}
