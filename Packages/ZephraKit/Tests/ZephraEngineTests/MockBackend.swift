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

    /// A 2x2 frame whose red channel counts the step, so a test can tell one frame from the
    /// next without decoding anything.
    static func preview(step: Int) -> GenerationPreview {
        GenerationPreview(
            width: 2, height: 2,
            pixels: Data((0..<4).flatMap { _ in [UInt8(step % 256), 0, 0, 255] }))
    }

    private(set) var loadedModelID: String?

    private let control: MockBackendControl

    init(control: MockBackendControl) {
        self.control = control
    }

    func availability(
        of descriptor: ModelDescriptor, locations: ModelLocations
    ) async -> ModelAvailability {
        control.update { $0.availabilityChecks += 1 }
        return control.settings.availability[descriptor.id] ?? .available
    }

    func ensureAvailable(
        _ descriptor: ModelDescriptor,
        locations: ModelLocations,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        control.update { $0.lastLocations = locations }
        onProgress(DownloadProgressEvent(completedFiles: 0, totalFiles: 2, fraction: 0))
        if control.settings.downloadDelay > .zero {
            try await Task.sleep(for: control.settings.downloadDelay)
        }
        try Task.checkCancellation()
        onProgress(DownloadProgressEvent(completedFiles: 2, totalFiles: 2, fraction: 1))
        return locations.downloads(repoID: descriptor.id)
    }

    func build(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        locations: ModelLocations,
        onProgress: @escaping @Sendable (BuildProgressEvent) -> Void
    ) async throws -> URL {
        let dials = control.settings
        guard dials.buildEvents > 0 else { return localPath }
        control.update { $0.builds += 1 }
        for step in 1...dials.buildEvents {
            try Task.checkCancellation()
            if dials.buildDelay > .zero {
                try await Task.sleep(for: dials.buildDelay)
            }
            onProgress(
                BuildProgressEvent(
                    component: "transformer", completedComponents: step,
                    totalComponents: dials.buildEvents,
                    fraction: Double(step) / Double(dials.buildEvents)))
        }
        return localPath.appending(path: "built")
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
        control.update { $0.generations += 1; $0.lastSettings = settings }
        let dials = control.settings
        if let error = dials.generateError { throw error }
        onProgress(GenerationProgressEvent(phase: .encodingText, fraction: 0))
        let total = max(1, dials.stepOverride ?? settings.steps)
        for step in 1...total {
            try Task.checkCancellation()
            if dials.stepDelay > .zero {
                try await Task.sleep(for: dials.stepDelay)
            }
            var preview: GenerationPreview?
            if dials.previewsEveryStep {
                preview = Self.preview(step: step)
                control.update { $0.previewsEmitted += 1 }
            }
            control.update { $0.stepsEmitted += 1 }
            onProgress(
                GenerationProgressEvent(
                    phase: .denoising(step: step, of: total),
                    fraction: Double(step) / Double(total),
                    preview: preview
                )
            )
        }
        try Task.checkCancellation()
        onProgress(GenerationProgressEvent(phase: .decoding, fraction: 1))
        return Self.pngData
    }

    func unload() {
        control.update { $0.unloads += 1 }
        loadedModelID = nil
    }
}
