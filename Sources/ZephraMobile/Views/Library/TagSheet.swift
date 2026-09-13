import SwiftUI

/// The tags on one picture, added and taken off.
///
/// The tags live in the picture's own PNG, so this is asking the Mac to rewrite a file: the
/// sheet keeps its own list while it is up and sends the whole list once, on Done. A tag added
/// and taken off again before Done is a file the Mac never touched.
///
/// The tags already in the library are offered underneath, which is most of what anybody
/// wants: a vocabulary of six words used over and over, not six hundred typed fresh each time.
struct TagSheet: View {
    /// The picture being tagged.
    let entry: CachedEntry

    @Environment(LibraryCatalog.self) private var catalog
    /// The list as it stands, which is what Done sends.
    @State private var tags: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Tags") {
                    TagField(tags: $tags)
                }
                if !suggestions.isEmpty {
                    Section("Already in your library") {
                        TagSuggestions(tags: suggestions) { tags.append($0) }
                    }
                }
            }
            .navigationTitle(entry.isVideo ? "Tag Clip" : "Tag Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DismissSheetButton(title: "Cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    DismissSheetButton(title: "Done", action: save)
                }
            }
            .task { tags = entry.tags }
        }
    }

    /// Every tag the library knows that this picture has not got.
    private var suggestions: [String] {
        catalog.knownTags.filter { !tags.contains($0) }
    }

    /// Sends the list. The catalog puts the tags on screen at once and takes them off again if
    /// the Mac refuses, so nothing here waits for an answer.
    private func save() {
        Task { await catalog.setTags([entry.id], tags: tags) }
    }
}

/// The library's own tags, offered as tokens to press.
private struct TagSuggestions: View {
    let tags: [String]
    let onChoose: (String) -> Void

    var body: some View {
        TagFlow(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Button { onChoose(tag) } label: { TagToken(title: tag) }
                    .buttonStyle(.plain)
            }
        }
    }
}
