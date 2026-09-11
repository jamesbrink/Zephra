import ZephraCore
import ZephraEngine

/// Flattening the engine's own state into the one the phone reads.
///
/// The mapping lives beside the DTO rather than on the Mac's side of the seam, so adding a case
/// to `EngineState` fails to compile here — in the package both ends share — rather than
/// silently reaching the phone as `idle`.
extension EngineStateDTO {
    /// The wire form of one engine state.
    public init(_ state: EngineState, modelID: String? = nil) {
        var dto: EngineStateDTO
        switch state {
        case .idle: dto = EngineStateDTO(kind: .idle)
        case .checkingModel: dto = EngineStateDTO(kind: .checkingModel)
        case .downloading(let event):
            dto = EngineStateDTO(
                kind: .downloading, fraction: event.fraction,
                completedBytes: event.completedBytes, totalBytes: event.totalBytes,
                completedFiles: event.completedFiles, totalFiles: event.totalFiles,
                bytesPerSecond: event.bytesPerSecond)
        case .building(let event):
            dto = EngineStateDTO(
                kind: .building, fraction: event.fraction, component: event.component,
                completedComponents: event.completedComponents,
                totalComponents: event.totalComponents)
        case .loading(let phase):
            dto = EngineStateDTO(kind: .loading, phase: Self.name(of: phase))
        case .warmingUp: dto = EngineStateDTO(kind: .warmingUp)
        case .ready: dto = EngineStateDTO(kind: .ready)
        case .generating(let event): dto = Self.generating(event)
        case .upscaling(let event):
            dto = EngineStateDTO(
                kind: .upscaling, fraction: event.fraction,
                completedTiles: event.completedTiles, totalTiles: event.totalTiles)
        case .cancelling: dto = EngineStateDTO(kind: .cancelling)
        case .failed(let error):
            dto = EngineStateDTO(kind: .failed, message: error.message)
        }
        dto.modelID = modelID
        dto.isBusy = state.isBusy
        dto.acceptsGeneration = state.acceptsGeneration
        self = dto
    }

    private static func generating(_ event: GenerationProgressEvent) -> EngineStateDTO {
        var dto = EngineStateDTO(
            kind: .generating, phase: name(of: event.phase), fraction: event.fraction,
            secondsPerStep: event.secondsPerStep)
        if case .denoising(let step, let total) = event.phase {
            dto.step = step
            dto.steps = total
        }
        switch event.phase {
        case .decoding, .saving: dto.isFinishing = true
        case .preparing, .encodingText, .denoising: dto.isFinishing = false
        }
        return dto
    }

    /// A phase as the one word the phone shows for it.
    private static func name(of phase: GenerationPhase) -> String {
        switch phase {
        case .preparing: "Preparing"
        case .encodingText: "Reading the prompt"
        case .denoising: "Denoising"
        case .decoding: "Decoding"
        case .saving: "Saving"
        }
    }
}
