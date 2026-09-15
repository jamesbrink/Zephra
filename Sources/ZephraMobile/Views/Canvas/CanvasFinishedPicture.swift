import SwiftUI

/// One host's finished picture opens the same full-screen viewer as its library entry.
struct CanvasFinishedPicture: View {
    let name: String
    @Environment(LibraryCatalog.self) private var catalog
    @State private var viewing: CachedEntry?

    var body: some View {
        Button {
            viewing = catalog.entry(named: name)
        } label: {
            ItemPicture(name: name)
        }
        .buttonStyle(.plain)
        .disabled(catalog.entry(named: name) == nil)
        .accessibilityLabel("Open image full screen")
        .contextMenu {
            if let entry = catalog.entry(named: name) {
                GenerationActions(entry: entry)
                UpscaleActions(entry: entry)
            }
        }
        .modifier(GenerationActionsReader())
        .modifier(UpscaleRequests())
        .modifier(PromptRequests())
        .fullScreenCover(item: $viewing) { entry in
            LibraryViewer(entries: [entry], opening: entry.id)
        }
    }
}
