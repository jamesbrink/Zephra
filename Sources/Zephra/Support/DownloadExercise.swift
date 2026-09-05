#if DEBUG
import Foundation
import ZephraCore
import ZephraEngine
import ZephraSnapshot

/// The explicit loopback-only test hook is inert in ordinary Debug runs and absent in Release.
nonisolated enum DownloadExercise {
    @MainActor
    static func makeStore() -> GenerationStore? {
        guard let host = ProcessInfo.processInfo.environment["ZEPHRA_DOWNLOAD_TEST_HUB"],
              let url = URL(string: host), url.host == "127.0.0.1", url.scheme == "http" else { return nil }
        var registry = BackendRegistry()
        for model in ModelCatalog.all { registry.register(model.backend) { _ in DownloadExerciseBackend() } }
        return GenerationStore(descriptor: ModelCatalog.flux2Klein4bit, registry: registry,
            outputDirectory: AppSettings.imageLibrary().root,
            locations: AppSettings.modelLocations(),
            downloads: ModelDownloads(transfers: ModelTransfers(downloader: ModelDownloader(host: url))))
    }
}
#endif
