import Foundation
import ZephraEngine
import ZephraLinkProtocol

/// Where the engine is, as the phone reads it, with the one fact the state alone cannot answer.
///
/// `EngineStateDTO(_ state:)` flattens `EngineState` and nothing else, which is right: it lives
/// in the package both ends share, and a new case of the engine's must fail to compile there.
/// But whether a generation may be *queued* is the store's fact, not the state's — a Mac with a
/// run in flight is rendering and will still take another behind it — so the store stamps it
/// here, at the one place the DTO is built for a phone. Both projection sites go through this;
/// a second site building the DTO by hand is a phone whose Generate button disagrees with the
/// Mac that refuses it.
@MainActor
public enum EngineStateProjection {
    /// The engine as it stands, ready to send.
    public static func engine(_ store: GenerationStore) -> EngineStateDTO {
        var dto = EngineStateDTO(store.state, modelID: store.descriptor.id)
        dto.canQueue = store.acceptsQueuedGeneration
        // Which model is *loaded* is the store's fact too, and under on-demand loading it is a
        // different model from the chosen one — or none at all.
        dto.loadedModelID = store.loadedDescriptor?.id
        return dto
    }
}
