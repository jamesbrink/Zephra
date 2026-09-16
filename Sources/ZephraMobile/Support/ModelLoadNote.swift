import ZephraCore
import ZephraLinkProtocol

/// What a press of Generate has the Mac do before it renders anything.
///
/// The Mac's own `ModelLoadNote` in a phone's shape and for its reason: under on-demand loading
/// a Mac stands idle with a model chosen and nothing read in, its `canQueue` is true because the
/// press would load it, and a button that offered no word for that would read as a press that
/// does nothing for a minute and a half.
///
/// The Mac's is a tooltip fragment and this is a whole line, which is the only difference; the
/// three answers and their order are its.
enum ModelLoadNote {
    /// "Loads klein 4-bit first", or nil where the weights are already in and the press just
    /// runs. Nil too for a Mac that has said nothing yet, since there is nothing to promise.
    static func text(
        name: String, modelID: String, engine: EngineStateDTO?, availability: AvailabilityDTO?
    ) -> String? {
        guard let engine, engine.loadedModelID != modelID else { return nil }
        switch availability?.kind {
        case .needsDownload, .needsDownloadAndBuild:
            guard let bytes = availability?.bytes else { return "Downloads \(name) first" }
            return "Downloads \(ByteCount.gigabytes(bytes)) for \(name) first"
        case .needsBuild:
            return "Builds \(name) first"
        default:
            return "Loads \(name) first"
        }
    }
}
