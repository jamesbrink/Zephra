import Foundation
import ZephraCore

extension GenerationStore {
    /// Creates a store for one model, running on the backends `registry` knows how to build.
    /// `outputDirectory` nil means ~/Pictures/Zephra.
    public convenience init(
        descriptor: ModelDescriptor = ModelCatalog.default,
        registry: BackendRegistry,
        outputDirectory: URL? = nil,
        locations: ModelLocations = .default,
        upscaler: UpscalerFactory? = nil, downloads: ModelDownloads = ModelDownloads()
    ) {
        self.init(
            descriptor: descriptor, registry: registry, output: outputDirectory,
            locations: locations, upscaler: upscaler, downloads: downloads)
    }
}
