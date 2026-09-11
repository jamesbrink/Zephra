import SwiftUI
import ZephraLinkClient
import ZephraStyle

/// The Mac's library, as a grid to pick a reference picture out of.
///
/// Deliberately plain: thumbnails, newest first, over whatever page of the library the phone
/// has been told about. The library surface proper — its scopes, its search, its albums — is
/// being built next door, and when it lands this becomes a use of it rather than a second
/// grid. Picking fetches the whole picture, because a thumbnail is not what a model reads.
struct ReferencePickerSheet: View {
    @Environment(LinkClient.self) private var client
    @Environment(PromptDraft.self) private var draft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(client.library) { entry in
                        Button {
                            adopt(entry.fileName)
                        } label: {
                            LibraryThumbnail(name: entry.fileName)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(MobileChrome.sideMargin)
            }
            .background(Color.canvasBackground)
            .navigationTitle("Choose a Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .overlay {
                if client.library.isEmpty {
                    ContentUnavailableView(
                        "No pictures yet", systemImage: "square.grid.2x2",
                        description: Text("Your Mac's library appears here."))
                }
            }
        }
    }

    private static let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    /// Fetches the picture itself and hands it to the well, naming the file it came from: the
    /// origin is provenance the Mac records beside the run.
    private func adopt(_ name: String) {
        guard let snapshot = client.snapshot else { return }
        let capabilities = snapshot.model(named: draft.modelID).capabilities
        dismiss()
        Task {
            guard let data = try? await client.file(name: name) else { return }
            await ReferenceAdoption.adopt(
                data, origin: name, into: draft, fitting: capabilities)
        }
    }
}
