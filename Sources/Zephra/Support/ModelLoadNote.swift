import ZephraCore
import ZephraEngine

/// What pressing Generate would do first, when the model that would run is not the one
/// resident: nothing, when `target` is already `store.modelInUse`, else what loading it costs.
///
/// One function rather than a copy in every button that names a model before it is chosen:
/// `GenerateButton`'s own tooltip reads `store.descriptor`, the model already chosen, and
/// `AnimateButton`'s reads the clip model speculatively, before Animate has been pressed and
/// while some other model is still the one in use.
enum ModelLoadNote {
    /// A sentence fragment starting with ". ", or the empty string when `target` needs nothing
    /// loaded first.
    @MainActor
    static func text(for target: ModelDescriptor, store: GenerationStore) -> String {
        guard target.id != store.modelInUse?.id else { return "" }
        let name = target.fullName
        switch store.availability[target.id] {
        case .needsDownload(let bytes), .needsDownloadAndBuild(let bytes):
            return ". Downloads \(ByteCount.gigabytes(bytes)) for \(name) first"
        case .needsBuild:
            return ". Builds \(name) first"
        default:
            return ". Loads \(name) first"
        }
    }
}
