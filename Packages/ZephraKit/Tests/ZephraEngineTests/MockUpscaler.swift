import Foundation
import ZephraCore

/// An upscaler that does everything the real one does except arithmetic: it reports a tile at a
/// time, honours cancellation between tiles, and hands back a real if tiny PNG.
///
/// The result is a *different* picture of a *different* size from the one the mock backend
/// generates — two pixels square against one — so a test asserting the result's width and
/// height is asserting that the size was read from what came back, not from what went in.
final class MockUpscaler: ImageUpscaler {
    /// A 2x2 opaque PNG, four flat colours. Deliberately not the backend's 1x1.
    static let pngData = Data(
        base64Encoded: """
            iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR42mP4z8DAAMIM\
            ////ZwAAHu8E/HMcU8wAAAAASUVORK5CYII=
            """
    )!

    private let control: MockUpscalerControl

    init(control: MockUpscalerControl) {
        self.control = control
    }

    func upscale(
        _ png: Data,
        _ request: UpscaleRequest,
        onProgress: @escaping (UpscaleProgressEvent) -> Void
    ) async throws -> Data {
        control.update { $0.upscales += 1; $0.lastFactor = request.factor }
        let dials = control.settings
        if let error = dials.error { throw error }
        let total = max(1, dials.tiles)
        for tile in 1...total {
            try Task.checkCancellation()
            if dials.tileDelay > .zero {
                try await Task.sleep(for: dials.tileDelay)
            }
            control.update { $0.tilesEmitted += 1 }
            onProgress(UpscaleProgressEvent(completedTiles: tile, totalTiles: total))
        }
        try Task.checkCancellation()
        return Self.pngData
    }

    func unload() {
        control.update { $0.unloads += 1 }
    }
}
