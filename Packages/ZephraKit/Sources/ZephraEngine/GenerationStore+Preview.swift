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
        outputDirectory: URL? = nil
    ) -> GenerationStore {
        let store = GenerationStore(descriptor: descriptor, registry: nil, output: outputDirectory)
        store.state = state
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
    private static func previewAvailability(
        current: ModelDescriptor
    ) -> [ModelDescriptor.ID: ModelAvailability] {
        var map: [ModelDescriptor.ID: ModelAvailability] = [current.id: .available]
        for model in ModelCatalog.all where model.id != current.id {
            switch model.source {
            case .huggingFace:
                map[model.id] =
                    model.isBuiltLocally
                    ? .needsDownloadAndBuild(bytes: model.downloadBytes)
                    : .needsDownload(bytes: model.downloadBytes)
            case .localDirectory: map[model.id] = .missing(reason: "Not built yet; run make quantize.")
            }
        }
        return map
    }
}
