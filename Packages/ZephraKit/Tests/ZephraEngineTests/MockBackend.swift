import Foundation
import ZephraCore

/// A backend that does everything the real one does except arithmetic: it reports download and
/// denoising progress, honours cancellation between steps, and returns a real if tiny PNG.
final class MockBackend: ImageGenerationBackend {
    static let backendID: BackendID = .zImage

    /// A 1x1 transparent PNG, so anything that decodes the result gets a valid image.
    static let pngData = Data(
        base64Encoded: """
            iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ\
            DwAEhQGAhKmMIQAAAABJRU5ErkJggg==
            """
    )!

    private(set) var loadedModelID: String?

    private let control: MockBackendControl

    init(control: MockBackendControl) {
        self.control = control
    }

    func ensureAvailable(
        _ descriptor: ModelDescriptor,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        onProgress(DownloadProgressEvent(completedFiles: 0, totalFiles: 2, fraction: 0))
        onProgress(DownloadProgressEvent(completedFiles: 2, totalFiles: 2, fraction: 1))
        return URL(filePath: NSTemporaryDirectory()).appending(path: descriptor.id)
    }

    func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {
        control.update { $0.loads += 1 }
        let dials = control.settings
        if let error = dials.loadError { throw error }
        onProgress(GenerationProgressEvent(phase: .preparing, fraction: 0))
        if dials.loadDelay > .zero {
            try await Task.sleep(for: dials.loadDelay)
        }
        try Task.checkCancellation()
        loadedModelID = descriptor.id
    }

    func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> Data {
        control.update { $0.generations += 1 }
        let dials = control.settings
        if let error = dials.generateError { throw error }
        onProgress(GenerationProgressEvent(phase: .encodingText, fraction: 0))
        let total = max(1, dials.stepOverride ?? settings.steps)
        for step in 1...total {
            try Task.checkCancellation()
            if dials.stepDelay > .zero {
                try await Task.sleep(for: dials.stepDelay)
            }
            control.update { $0.stepsEmitted += 1 }
            onProgress(
                GenerationProgressEvent(
                    phase: .denoising(step: step, of: total),
                    fraction: Double(step) / Double(total)
                )
            )
        }
        try Task.checkCancellation()
        onProgress(GenerationProgressEvent(phase: .decoding, fraction: 1))
        return Self.pngData
    }

    func unload() {
        loadedModelID = nil
    }
}
