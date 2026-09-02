import ZephraCore

/// A store that only pretends, for SwiftUI previews and for the screenshot builds driven by
/// `ZEPHRA_PREVIEW_STATE`. It has no backend at all, so nothing it is asked to do can reach
/// one: `bootstrap` returns immediately and a generation never starts.
extension GenerationStore {
    /// A store frozen in one state. Never touches a backend, and never loads a model.
    public static func preview(state: EngineState, image: GeneratedImage? = nil) -> GenerationStore {
        let store = GenerationStore(descriptor: ModelCatalog.default, factory: nil, outputDirectory: nil)
        store.state = state
        store.current = image
        store.history = image.map { [$0] } ?? []
        store.settings.prompt = "A lighthouse at dusk, fog rolling in over black rocks"
        return store
    }
}
