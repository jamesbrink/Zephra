import PhotosUI
import SwiftUI
import ZephraLinkClient

/// The camera roll door: a photo off this phone into the well.
///
/// `PhotosPicker` asks for one picture and hands back its bytes without the app ever holding a
/// permission of its own — the person picks in Apple's own sheet, and only what they picked
/// crosses. Everything after that is `ReferenceAdoption`'s, so this door and the Mac's library
/// door apply the same rules.
struct ReferencePhotoButton: View {
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(PromptDraft.self) private var draft
    @Environment(ReferenceIntent.self) private var intent

    var body: some View { ReferencePhotoPicker(choose: adopt) }

    private func adopt(_ picked: PhotosPickerItem) {
        // The revision belongs to the user's tap, before asynchronous work can be scheduled.
        intent.beginSelection()
        let revision = intent.revision
        Task {
            await ReferenceAdoption.resolve(intent, revision: revision,
                load: { try? await picked.loadTransferable(type: Data.self) }) { picture in
                guard let model = dispatch.models.first(where: { $0.id == draft.modelID }) else { return false }
                draft.adopt(picture, origin: nil, fitting: model.capabilities.capabilities)
                return true
            }
        }
    }
}
