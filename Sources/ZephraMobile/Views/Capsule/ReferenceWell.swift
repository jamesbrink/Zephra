import SwiftUI
import ZephraCore
import ZephraLinkProtocol
import ZephraStyle

/// What the next run starts from: one picture on a model that reads one, a strip of them on a
/// model that reads several, a caption saying what the pictures are *for*, and the doors they
/// come in through.
///
/// The caption is `ReferenceRole`'s, so the phone calls a clip's first frame a first frame and
/// a picture to edit a reference, in the Mac's own words rather than in a second set that could
/// drift; the plural is that same type's (`ReferenceRole+Count`). The doors are the camera roll
/// and the Mac's own library, and both lead to the same rules in `PromptDraft+ReferenceStrip`.
struct ReferenceWell: View {
    /// What the model in force will accept, which decides the caption and how many pictures fit.
    let capabilities: CapabilitiesSummary
    @Environment(PromptDraft.self) private var draft
    @Environment(ReferenceIntent.self) private var intent

    var body: some View {
        VStack(spacing: 6) {
            if capabilities.capabilities.acceptsSeveralReferences {
                ReferenceStrip(capabilities: capabilities)
            } else {
                ReferenceSlotView(picture: draft.references.first)
            }
            Text(ReferenceRole(capabilities: capabilities.capabilities).wellCaption(count: plural))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize()
            HStack(spacing: 8) {
                ReferencePhotoButton(capabilities: capabilities.capabilities)
                ReferenceLibraryButton(
                    room: draft.referenceRoom(for: capabilities.capabilities))
                if !draft.references.isEmpty {
                    Button {
                        intent.clear()
                        draft.clearReferences()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(
                        draft.references.count > 1 ? "Clear the pictures" : "Clear the picture")
                }
            }
            .font(.caption)
        }
    }

    /// What the caption counts. An empty strip on a model that reads ten is still "References":
    /// the word is about what the well is for, and it would read as a different well the moment
    /// the first picture landed.
    private var plural: Int {
        max(draft.references.count, capabilities.capabilities.acceptsSeveralReferences ? 2 : 1)
    }
}
