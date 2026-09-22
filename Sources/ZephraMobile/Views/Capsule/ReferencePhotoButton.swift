import PhotosUI
import SwiftUI
import ZephraCore

/// The camera roll door: photos off this phone into the well.
///
/// `PhotosPicker` asks for as many pictures as the well has room for and hands back their bytes
/// without the app ever holding a permission of its own — the person picks in Apple's own
/// sheet, and only what they picked crosses. Everything after that is `ReferenceAdoption`'s and
/// `PromptDraft+ReferenceStrip`'s, so this door and the Mac's library door apply the same rules.
struct ReferencePhotoButton: View {
    /// What the model in force will accept, which says how many pictures may be chosen.
    let capabilities: ModelCapabilities
    @Environment(PromptDraft.self) private var draft
    @Environment(ReferenceIntent.self) private var intent

    var body: some View {
        ReferencePhotoPicker(
            maximum: max(1, draft.referenceRoom(for: capabilities)), choose: adopt)
    }

    private func adopt(_ picked: [PhotosPickerItem]) {
        // The revision belongs to the user's tap, before asynchronous work can be scheduled.
        intent.beginSelection()
        let revision = intent.revision
        let capabilities = capabilities
        Task {
            await ReferenceAdoption.resolve(intent, revision: revision, load: {
                var pictures: [ReferencePicture] = []
                for item in picked {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                        let picture = await ReferenceAdoption.encoded(data)
                    else { continue }
                    pictures.append(picture)
                }
                return pictures
            }) { pictures in
                draft.useAsReferences(pictures, fitting: capabilities)
            }
        }
    }
}
