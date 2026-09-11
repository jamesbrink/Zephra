import ZephraCore
import ZephraEngine

/// Why "Use as Reference" or "Animate" is disabled, when it is.
///
/// The macOS convention both buttons follow is disabled rather than hidden, and a control that
/// greys out ought to say why: `UseAsReferenceButton`, `FreshImageActions`, `FreshImageMenu` and
/// `AnimateButton` all read this rather than spelling their own reasons, so the four cannot say
/// four different things about the same disablement.
enum ActionAvailability {
    /// "Use as Reference"'s reason, or "" once the model reads a picture and the button is live.
    static func referenceDisabledReason(capabilities: ModelCapabilities) -> String {
        capabilities.supportsReferenceImage ? "" : "This model does not read a picture"
    }

    /// Whether `image` itself has bytes Animate could read: a picture, or a clip already on
    /// disk or still held in memory with its MP4 beside the poster. False only for a clip whose
    /// write has not landed and whose video never reached memory either — practically never for
    /// a session's own picture, but worth naming so the button can say why rather than merely
    /// refusing; see `ReferenceAdoption.animate(_:into:)`.
    static func hasAnimatableSource(_ image: GeneratedImage) -> Bool {
        guard image.isVideo else { return true }
        return image.fileURL != nil || image.video != nil
    }

    /// Extend Clip's reason over a clip whose record is `record` (nil while the session's own
    /// clip has not been written yet, since the join needs the source on disk), or "" once it
    /// is live. `ExtendClipButton`, `FreshImageActions` and `FreshImageMenu` read it.
    @MainActor
    static func extendDisabledReason(record: GenerationRecord?, store: GenerationStore) -> String {
        guard store.clips != nil, ModelCatalog.animator() != nil else {
            return "This build cannot carry a clip on"
        }
        guard store.acceptsWork else { return "Wait for the current work to finish" }
        guard let record else { return "This clip has not finished saving yet" }
        guard store.canExtend(record) else { return "This clip's size is not one its model can continue" }
        return ""
    }

    /// Animate's reason over a picture with `hasSource`, in `store`, or "" once it is live.
    /// `AnimateButton` always has one (a `LibraryItem` is already on disk); `FreshImageActions`
    /// and `FreshImageMenu` pass `hasAnimatableSource(image)`.
    @MainActor
    static func animateDisabledReason(hasSource: Bool, store: GenerationStore) -> String {
        guard ModelCatalog.animator() != nil else {
            return "No installed model makes clips from a picture"
        }
        guard store.acceptsWork else { return "Wait for the current work to finish" }
        guard hasSource else { return "This clip has not finished saving yet" }
        return ""
    }
}
