import SwiftUI
import ZephraStyle

/// The strip under a picture in the viewer: favorite, share, save, and everything else.
///
/// Four controls, which is the whole of what somebody does with a picture they are looking at.
/// The rest is behind More, which is the same `LibraryItemMenu` the grid's cells wear — one
/// list of actions for the app, so nothing is offered in one place and missing in the other.
///
/// Each save or share owns the file until its consumer finishes, independently of the viewer.
struct LibraryViewerBar: View {
    /// The picture the bar is about.
    let entry: CachedEntry

    @Environment(LibraryCatalog.self) private var catalog
    /// The file on this phone, once it is here.
    @State private var availability = MediaAvailability()
    private var action: MediaAction { availability.action }

    var body: some View {
        HStack(spacing: 26) {
            Button {
                Task { await catalog.setFavourite([entry.id], on: !entry.isFavourite) }
            } label: {
                Image(systemName: entry.isFavourite ? "star.fill" : "star")
            }
            .disabled(!catalog.isLive(for: entry))
            .accessibilityLabel(entry.isFavourite ? "Remove from Favorites" : "Add to Favorites")

            Button {
                Task { await action.share { try await catalog.leasedMedia(for: entry) } }
            } label: { Image(systemName: "square.and.arrow.up") }
            .accessibilityLabel("Share")
            .disabled(action.busy || (!catalog.isLive(for: entry) && !availability.isHeld))
            PhotoSaveButton(entry: entry)
                .labelStyle(.iconOnly)
                .disabled(action.busy || (!catalog.isLive(for: entry) && !availability.isHeld))

            Menu {
                LibraryItemMenu(entry: entry)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.black.opacity(MobileChrome.viewerChromeOpacity), in: Capsule())
        .padding(.bottom, 28)
        .task(id: entry.id + entry.version + String(catalog.cacheRevision) + String(catalog.isLive(for: entry))) {
            let held = await catalog.hasFile(for: entry)
            if !Task.isCancelled { availability.isHeld = held }
        }
        .modifier(MediaActionFeedback(action: action))
        .sheet(isPresented: Binding(get: { action.sharing != nil }, set: { if !$0 { action.sharing = nil } })) {
            if let media = action.sharing { ShareSheet(url: media.url) }
        }

    }
}

#Preview("Viewer bar") {
    LibraryViewerBar(entry: CachedEntry(MobilePreview.library()[0]))
        .padding(40)
        .background(.gray)
        .environment(LibraryCatalog(libraryRoot: nil, filesRoot: nil))
        .environment(ReferenceIntent())
        .environment(MobileSelection())
}
