import SwiftUI
import ZephraEngine

/// "Add to Album", with a tick beside each album the images are already in.
///
/// Choosing a ticked album takes them out again, so the menu is a set of switches rather than a
/// list of one-way doors — which is what a tick means everywhere else on the Mac.
///
/// "New Album…" holds the name it is collecting in one optional, which is both what is being
/// typed and whether anything is being asked at all. There is no way to reach a state where the
/// field is showing yesterday's word.
struct AlbumMenu: View {
    /// The images the menu files.
    let ids: Set<LibraryItem.ID>

    @Environment(LibraryIndex.self) private var index
    @State private var newName: String?

    var body: some View {
        Menu("Add to Album") {
            ForEach(index.albums) { album in
                Button {
                    if holdsAll(album) {
                        index.remove(ids, from: album)
                    } else {
                        index.add(ids, to: album)
                    }
                } label: {
                    if holdsAll(album) {
                        Label(album.name, systemImage: "checkmark")
                    } else {
                        Text(album.name)
                    }
                }
            }
            if !index.albums.isEmpty { Divider() }
            Button("New Album…") { newName = "" }
        }
        .alert("New Album", isPresented: isNaming) {
            TextField("Name", text: name)
                .onSubmit(create)
            Button("Create", action: create)
                .disabled(name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { newName = nil }
        }
    }

    private func create() {
        guard let typed = newName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !typed.isEmpty
        else { return }
        newName = nil
        index.add(ids, to: index.createAlbum(named: typed))
    }

    private func holdsAll(_ album: Album) -> Bool {
        !ids.isEmpty && ids.allSatisfy { id in
            index.item(for: id)?.annotation.albums.contains { $0.id == album.id } == true
        }
    }

    private var isNaming: Binding<Bool> {
        Binding(get: { newName != nil }, set: { if !$0 { newName = nil } })
    }

    private var name: Binding<String> {
        Binding(get: { newName ?? "" }, set: { newName = $0 })
    }
}
