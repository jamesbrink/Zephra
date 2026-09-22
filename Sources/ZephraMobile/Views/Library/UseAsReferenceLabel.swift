import SwiftUI

/// What "Use as Reference" is called, which depends on what the well already holds.
///
/// D7 says a picture is added where there is room and replaces the strip where there is not, so
/// the word has to say which: "Add to References" over a strip with room, "Use as Reference"
/// over an empty well and over a full one, where the press starts afresh with the one chosen.
/// It reads `PromptDraft.referenceRoom(for:)` — the same answer the press itself reads — so the
/// label and the press cannot come to differ.
///
/// A view of its own because the button beside it already holds the picture, the intent and
/// where the phone is looking, and this needs two objects of its own.
struct UseAsReferenceLabel: View {
    @Environment(PromptDraft.self) private var draft
    @Environment(GenerationDispatch.self) private var dispatch

    var body: some View {
        Label(adds ? "Add to References" : "Use as Reference", systemImage: "photo.badge.plus")
    }

    /// Whether the press would add to what is in the well rather than replace it. An empty well
    /// is not something to add to, whatever room it has.
    private var adds: Bool {
        guard !draft.references.isEmpty,
            let model = dispatch.models.first(where: { $0.id == draft.modelID })
        else { return false }
        return draft.referenceRoom(for: model.capabilities.capabilities) > 0
    }
}
