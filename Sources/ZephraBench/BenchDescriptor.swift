import Foundation
import ZephraCore

/// A throwaway descriptor for a model the catalog does not carry yet.
///
/// House rule is that every number in a `ModelCatalog` entry is measured, which leaves a
/// chicken-and-egg: the numbers come from this tool, and this tool takes a descriptor. So a
/// headless run can name a backend and a directory instead, and the memory figures here are
/// zero and stay inside the tool. `BenchRunner` reads only the capabilities, the identifier, the
/// source, and the prompt limit; it never asks `MemoryFit` anything.
enum BenchDescriptor {
    /// A descriptor for the snapshot at `directory`, run by `backend`.
    static func forSnapshot(
        _ directory: URL,
        backend: BackendID,
        size: Int,
        steps: Int
    ) -> ModelDescriptor {
        ModelDescriptor(
            id: directory.lastPathComponent,
            displayName: directory.lastPathComponent,
            variantName: "unmeasured",
            backend: backend,
            source: .localDirectory(directory),
            quantization: .int4,
            downloadBytes: 0,
            // Zero, and deliberately: these are what the run is for. Nothing in this tool reads
            // them, and they never reach the catalog.
            residentBytes: 0,
            peakBytes: 0,
            tiledPeakBytes: 0,
            maxPromptTokens: 1024,
            capabilities: ModelCapabilities(
                sizeAlignment: 16,
                sizePresets: [ImageSize(width: size, height: size)],
                sizeBounds: 256...2048,
                defaultSize: ImageSize(width: size, height: size),
                stepBounds: 1...50,
                defaultSteps: steps,
                guidanceBounds: 0...0,
                defaultGuidance: 0,
                supportsNegativePrompt: false,
                supportsSeed: true
            )
        )
    }
}
