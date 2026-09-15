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
/// Encoding stays synthesised over these same keys: what this Mac sends is simply everything
/// it has.
extension EngineStateDTO {
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
            loadedModelID: try container.decodeIfPresent(String.self, forKey: .loadedModelID)
                ?? (kind == .idle ? nil : modelID),
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
