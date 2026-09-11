import SwiftUI

/// What a picture's menu asked for, and the one place it is answered.
///
/// The tag sheet, the delete question and the share sheet all belong to whichever surface is
/// presenting — the grid, or the viewer over it — so this is a modifier rather than a view:
/// both apply it, each gets its own, and a sheet raised from inside a full-screen cover is
/// raised by the cover rather than by the grid behind it, which would show nothing at all.
///
/// One piece of state for all three. They are exclusive by nature: nobody is tagging a picture
/// and sharing another at the same time, and one `@State` is one thing to reason about.
struct LibraryRequests: ViewModifier {
    @Environment(LibraryCatalog.self) private var catalog
    /// What is being asked for right now, or nil.
    @State private var request: LibraryRequest?

    func body(content: Content) -> some View {
        content
            .environment(\.tagLibraryItem) { request = .tagging($0) }
            .environment(\.confirmDeleteLibraryItem) { request = .deleting($0) }
            .environment(\.shareLibraryItem, share)
            .sheet(item: $request) { sheet(for: $0) }
            .confirmationDialog(
                deleteTitle, isPresented: isDeleting, titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) { request = nil }
            } message: {
                Text("It moves to Recently Deleted on your Mac, where it stays for thirty days.")
            }
    }

    /// The sheet one request raises, if it raises one: the delete question is a dialog rather
    /// than a sheet, so it answers with nothing here.
    @ViewBuilder private func sheet(for request: LibraryRequest) -> some View {
        switch request {
        case .tagging(let entry): TagSheet(entry: entry)
        case .sharing(let url): ShareSheet(url: url)
        case .deleting: EmptyView()
        }
    }

    /// Fetches the file and then offers it, which is two steps because the bytes may not be on
    /// the phone yet. Nothing is raised if they cannot be got: the menu item is already greyed
    /// while the Mac is out of reach, so this is a link that dropped mid-fetch.
    private func share(_ entry: CachedEntry) {
        Task {
            guard let url = try? await catalog.file(for: entry) else { return }
            request = .sharing(url)
        }
    }

    /// Deletes what was asked about, on the Mac and here.
    private func delete() {
        guard case .deleting(let entry) = request else { return }
        request = nil
        Task { await catalog.delete([entry.fileName]) }
    }

    /// "Delete Clip" or "Delete Picture", so the question names what is about to go.
    private var deleteTitle: String {
        guard case .deleting(let entry) = request else { return "Delete" }
        return entry.isVideo ? "Delete Clip" : "Delete Picture"
    }

    /// Whether the delete question is up, which is exactly whether that is what was asked.
    private var isDeleting: Binding<Bool> {
        Binding(
            get: { if case .deleting = request { true } else { false } },
            set: { if !$0 { request = nil } })
    }
}

/// One thing a picture's menu asked a surface to put up.
enum LibraryRequest: Identifiable {
    /// Tag this picture.
    case tagging(CachedEntry)
    /// Ask whether to delete this one.
    case deleting(CachedEntry)
    /// Offer this file to the rest of the phone.
    case sharing(URL)

    var id: String {
        switch self {
        case .tagging(let entry): "tag:\(entry.fileName)"
        case .deleting(let entry): "delete:\(entry.fileName)"
        case .sharing(let url): "share:\(url.path())"
        }
    }
}
