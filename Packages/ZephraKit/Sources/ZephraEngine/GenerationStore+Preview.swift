import Foundation
import ZephraCore

/// A store that only pretends, for SwiftUI previews and for the screenshot builds driven by
/// `ZEPHRA_PREVIEW_STATE`. It has no backend registry at all, so nothing it is asked to do can
/// reach one: `bootstrap` returns immediately and a generation never starts.
extension GenerationStore {
    /// A store frozen in one state. Never touches a backend, and never loads a model.
    ///
    /// `descriptor` picks the model whose capabilities the controls are drawn from, so a
    /// preview can hand in an invented model to see the negative prompt and guidance appear.
    ///
    /// `images`, `running`, and `queue` stand a whole run up at once, which is the only way to
    /// see the sidebar's queue and the strip under the capsule without a backend: both are
    /// `internal(set)` on the real store, and rightly so.
    ///
    /// `loaded` is the model the frozen store says is in memory. Nothing is ever really loaded
    /// here, but a state the engine only reaches over loaded weights — ready, generating,
    /// warming up — would otherwise be photographed beside a toolbar offering to load one.
    ///
    /// `livePreview` is the frame the canvas would be showing. `following` overrides the rule
    /// below it, and `false` with a run standing up is the one state that cannot be reached any
    /// other way: the model working while the user looks at an earlier picture.
    public static func preview(
        state: EngineState,
        image: GeneratedImage? = nil,
        descriptor: ModelDescriptor = ModelCatalog.default,
        images: [GeneratedImage] = [],
        running: QueuedGeneration? = nil,
        queue: [QueuedGeneration] = [],
        livePreview: GenerationPreview? = nil,
        following: Bool? = nil,
        swappingModel: Bool = false,
        loaded: ModelDescriptor? = nil,
        residency: WeightResidency? = nil,
        outputDirectory: URL? = nil
    ) -> GenerationStore {
        let store = GenerationStore(descriptor: descriptor, registry: nil, output: outputDirectory)
        store.state = state
        store.loadedDescriptor = loaded
        store.loadedResidency = loaded == nil ? nil : (residency ?? .resident)
        store.isSwappingModel = swappingModel
        store.history = images.isEmpty ? image.map { [$0] } ?? [] : images
        store.current = image ?? store.history.first
        store.running = running
        store.queue = queue
        // A store standing a run up is a store that pressed Generate, so it is following it:
        // without this the canvas would draw the finished picture over a running generation and
        // the screenshot would show a state the app never reaches.
        store.followsRun = following ?? (running != nil)
        store.livePreview = livePreview
        store.settings.prompt = "A lighthouse at dusk, fog rolling in over black rocks"
        store.settings.referenceImage = image?.settings.referenceImage
        store.availability = previewAvailability(current: descriptor)
        return store
    }

    /// Made up, like everything else here: the chosen model reads as downloaded, a hub model as
    /// a download away, and a local variant as not built, so a picker has rows to label.
    ///
    /// A variant the mirror publishes ready-made is charged its packed size and not its
    /// release's, the way the real answer is: klein transfers 5.4 GB, not the 16 GB of bf16 it
    /// was packed from, and a screenshot of a picker quoting the release would be a screenshot
    /// of a number the app never shows.
    private static func previewAvailability(
        current: ModelDescriptor
    ) -> [ModelDescriptor.ID: ModelAvailability] {
        var map: [ModelDescriptor.ID: ModelAvailability] = [current.id: .available]
        for model in ModelCatalog.all where model.id != current.id {
            switch model.source {
            case .huggingFace:
                map[model.id] =
                    switch (model.isPublishedPrebuilt, model.isBuiltLocally) {
                    case (true, _): .needsDownload(bytes: model.builtBytes)
                    case (false, true): .needsDownloadAndBuild(bytes: model.transferBytes)
                    case (false, false): .needsDownload(bytes: model.transferBytes)
                    }
            case .localDirectory: map[model.id] = .missing(reason: "Not built yet; run make quantize.")
            }
        }
        return map
    }
}
