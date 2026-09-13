import SwiftUI
import ZephraCore
import ZephraLinkProtocol
import ZephraStyle

/// The picture the next run starts from, on a model that reads one: a square at the trailing
/// edge of the prompt, a caption saying what the picture is *for*, and the two doors it can
/// come in through.
///
/// The caption is `ReferenceRole`'s, so the phone calls a clip's first frame a first frame and
/// a picture to edit a reference, in the Mac's own words rather than in a second set that
/// could drift. The doors are the camera roll and the Mac's own library.
struct ReferenceWell: View {
    /// What the model in force will accept, which is what decides the caption.
    let capabilities: CapabilitiesSummary
    @Environment(PromptDraft.self) private var draft
    @Environment(ReferenceIntent.self) private var intent

    var body: some View {
        VStack(spacing: 6) {
            square
            Text(ReferenceRole(capabilities: capabilities.capabilities).wellCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize()
            HStack(spacing: 8) {
                ReferencePhotoButton()
                ReferenceLibraryButton()
                if draft.reference != nil {
                    Button {
                        intent.clear()
                        draft.clearReference()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Clear the picture")
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder private var square: some View {
        if let data = draft.reference {
            ReferenceThumbnail(data: data)
                .frame(width: 72, height: 72)
                .clipShape(
                    RoundedRectangle(cornerRadius: ZephraChrome.wellRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: ZephraChrome.wellRadius, style: .continuous)
                .fill(ZephraChrome.wellFill)
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
        }
    }
}
