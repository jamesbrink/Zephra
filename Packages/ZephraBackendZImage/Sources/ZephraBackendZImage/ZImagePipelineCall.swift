import Foundation
import ZephraCore
import ZImage

/// One call into the vendored pipeline, packaged so that the pipeline and the progress handler
/// arrive on the same executor together.
///
/// The two halves cannot meet otherwise. `ZImagePipeline` is a non-Sendable class from a
/// Swift 5 module, so its async methods run on the generic executor, while the
/// `ImageGenerationBackend` requirements run on the caller's executor and take a progress
/// handler that is deliberately not Sendable. Wrapping both in one `@unchecked Sendable` value
/// lets the pair cross that boundary exactly once, in a `@concurrent` method whose body is
/// then a single non-isolated context where the vendored call is an ordinary function call.
///
/// The unchecked conformance rests on a guarantee from the layer above rather than on the
/// compiler: the engine runs one backend call at a time, so the pipeline is only ever reached
/// from one task, and the pipeline invokes the handler synchronously inside the call it
/// belongs to. Cancellation is unaffected, because hopping executors keeps the same task, and
/// the pipeline checks for cancellation between denoising steps.
struct ZImagePipelineCall: @unchecked Sendable {
    /// The pipeline holding the weights.
    let pipeline: ZImagePipeline
    /// Where progress from this call should go.
    let onProgress: (GenerationProgressEvent) -> Void

    /// Reads the weights at `modelPath` into the pipeline.
    @concurrent func load(modelPath: String) async throws {
        try await pipeline.loadModel(modelSpec: modelPath) { progress in
            onProgress(ZImageProgressMapper.event(from: progress))
        }
    }

    /// Runs one generation and returns the encoded PNG bytes.
    @concurrent func generate(_ request: ZImageGenerationRequest) async throws -> Data {
        try await pipeline.generateToMemory(request) { progress in
            onProgress(ZImageProgressMapper.event(from: progress))
        }
    }
}
