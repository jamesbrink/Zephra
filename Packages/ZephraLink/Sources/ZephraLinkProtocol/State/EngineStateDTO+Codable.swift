import Foundation

/// Reading a state update written by a Mac that may be older than this phone.
///
/// Written by hand for two fields. `canQueue` was added after the first Macs shipped, and a
/// state without it is not a state that takes no queued work — it is a Mac that never had an
/// opinion. Read as absent it would grey out Generate for good against an older Mac, so it
/// falls back to `acceptsGeneration`, which is what "one at a time" meant before the field
/// existed. `loadedModelID` came later still, and its absence is read the same honest way: an
/// older Mac loaded whatever it had chosen, so `.idle` meant nothing was loaded and every other
/// case meant the chosen model was. `QueuedEntry` reads itself by hand for its own reason and is
/// the precedent.
///
/// Encoding is written by hand for the same one field. Every other key is omitted when it is
/// absent, as a synthesised encoder would omit it; `loadedModelID` is written **always**, null
/// included, because its absence is what says the far end is a Mac that never had the field. A
/// Mac that has it and has nothing loaded would otherwise be indistinguishable from one that
/// does not have it at all — and under on-demand loading that is the ordinary case, so the
/// phone would draw a loaded dot on a model that is not there.
extension EngineStateDTO {
    /// Writes a state update, always saying whether a model is loaded.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(phase, forKey: .phase)
        try container.encodeIfPresent(step, forKey: .step)
        try container.encodeIfPresent(steps, forKey: .steps)
        try container.encodeIfPresent(fraction, forKey: .fraction)
        try container.encodeIfPresent(secondsPerStep, forKey: .secondsPerStep)
        try container.encodeIfPresent(completedBytes, forKey: .completedBytes)
        try container.encodeIfPresent(totalBytes, forKey: .totalBytes)
        try container.encodeIfPresent(completedFiles, forKey: .completedFiles)
        try container.encodeIfPresent(totalFiles, forKey: .totalFiles)
        try container.encodeIfPresent(bytesPerSecond, forKey: .bytesPerSecond)
        try container.encodeIfPresent(component, forKey: .component)
        try container.encodeIfPresent(completedComponents, forKey: .completedComponents)
        try container.encodeIfPresent(totalComponents, forKey: .totalComponents)
        try container.encodeIfPresent(completedTiles, forKey: .completedTiles)
        try container.encodeIfPresent(totalTiles, forKey: .totalTiles)
        try container.encodeIfPresent(modelID, forKey: .modelID)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encode(loadedModelID, forKey: .loadedModelID)
        try container.encode(isBusy, forKey: .isBusy)
        try container.encode(isFinishing, forKey: .isFinishing)
        try container.encode(acceptsGeneration, forKey: .acceptsGeneration)
        try container.encode(canQueue, forKey: .canQueue)
    }

    /// Reads a state update, defaulting a field an older Mac does not send.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let acceptsGeneration = try container.decode(Bool.self, forKey: .acceptsGeneration)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        self.init(
            kind: kind,
            phase: try container.decodeIfPresent(String.self, forKey: .phase),
            step: try container.decodeIfPresent(Int.self, forKey: .step),
            steps: try container.decodeIfPresent(Int.self, forKey: .steps),
            fraction: try container.decodeIfPresent(Double.self, forKey: .fraction),
            secondsPerStep: try container.decodeIfPresent(Double.self, forKey: .secondsPerStep),
            completedBytes: try container.decodeIfPresent(Int64.self, forKey: .completedBytes),
            totalBytes: try container.decodeIfPresent(Int64.self, forKey: .totalBytes),
            completedFiles: try container.decodeIfPresent(Int.self, forKey: .completedFiles),
            totalFiles: try container.decodeIfPresent(Int.self, forKey: .totalFiles),
            bytesPerSecond: try container.decodeIfPresent(Double.self, forKey: .bytesPerSecond),
            component: try container.decodeIfPresent(String.self, forKey: .component),
            completedComponents: try container.decodeIfPresent(
                Int.self, forKey: .completedComponents),
            totalComponents: try container.decodeIfPresent(Int.self, forKey: .totalComponents),
            completedTiles: try container.decodeIfPresent(Int.self, forKey: .completedTiles),
            totalTiles: try container.decodeIfPresent(Int.self, forKey: .totalTiles),
            modelID: modelID,
            message: try container.decodeIfPresent(String.self, forKey: .message),
            // `.upscaling` and `.failed` read as loaded on purpose: an older Mac loads at
            // launch and a generate-time fault leaves the weights up, so both mean the model is.
            loadedModelID: container.contains(.loadedModelID)
                ? try container.decodeIfPresent(String.self, forKey: .loadedModelID)
                : (kind == .idle ? nil : modelID),
            isBusy: try container.decode(Bool.self, forKey: .isBusy),
            isFinishing: try container.decode(Bool.self, forKey: .isFinishing),
            acceptsGeneration: acceptsGeneration,
            canQueue: try container.decodeIfPresent(Bool.self, forKey: .canQueue)
                ?? acceptsGeneration)
    }

    enum CodingKeys: String, CodingKey {
        case kind, phase, step, steps, fraction, secondsPerStep, completedBytes, totalBytes
        case completedFiles, totalFiles, bytesPerSecond, component, completedComponents
        case totalComponents, completedTiles, totalTiles, modelID, message, isBusy, isFinishing
        case acceptsGeneration, canQueue, loadedModelID
    }
}
