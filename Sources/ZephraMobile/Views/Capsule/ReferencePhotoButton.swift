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
    @Environment(LinkClient.self) private var client
    @Environment(PromptDraft.self) private var draft
    /// What was picked, or nil.
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
            Image(systemName: "photo.on.rectangle")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Choose a photo")
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task { await adopt(picked) }
        }
    }

    private func adopt(_ picked: PhotosPickerItem) async {
        guard let snapshot = client.snapshot,
            let data = try? await picked.loadTransferable(type: Data.self)
        else { return }
        let capabilities = snapshot.model(named: draft.modelID).capabilities
        await ReferenceAdoption.adopt(data, origin: nil, into: draft, fitting: capabilities)
        item = nil
    }
}
