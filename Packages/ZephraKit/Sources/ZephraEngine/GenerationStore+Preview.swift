import ZephraCore

/// A store that only pretends, for SwiftUI previews and for the screenshot builds driven by
/// `ZEPHRA_PREVIEW_STATE`. It has no backend registry at all, so nothing it is asked to do can
/// reach one: `bootstrap` returns immediately and a generation never starts.
extension GenerationStore {
    /// A store frozen in one state. Never touches a backend, and never loads a model.
    ///
    /// `descriptor` picks the model whose capabilities the controls are drawn from, so a
    /// preview can hand in an invented model to see the negative prompt and guidance appear.
    public static func preview(
        state: EngineState,
        image: GeneratedImage? = nil,
        descriptor: ModelDescriptor = ModelCatalog.default
    ) -> GenerationStore {
        let store = GenerationStore(descriptor: descriptor, registry: nil, output: nil)
        store.state = state
        store.current = image
        store.history = image.map { [$0] } ?? []
        store.settings.prompt = "A lighthouse at dusk, fog rolling in over black rocks"
        store.availability = previewAvailability(current: descriptor)
        return store
    }

    /// Made up, like everything else here: the chosen model reads as downloaded and the rest of
    /// the catalog as a download away, so a picker has something to label its rows with.
    private static func previewAvailability(
        current: ModelDescriptor
    ) -> [ModelDescriptor.ID: ModelAvailability] {
        var map: [ModelDescriptor.ID: ModelAvailability] = [current.id: .available]
        for model in ModelCatalog.all where model.id != current.id {
            map[model.id] = .needsDownload(bytes: model.downloadBytes)
        }
        return map
    }
}
