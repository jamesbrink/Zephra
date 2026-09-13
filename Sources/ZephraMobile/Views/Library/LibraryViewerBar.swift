import SwiftUI
import ZephraStyle

/// The strip under a picture in the viewer: favorite, share, save, and everything else.
///
/// Four controls, which is the whole of what somebody does with a picture they are looking at.
/// The rest is behind More, which is the same `LibraryItemMenu` the grid's cells wear — one
/// list of actions for the app, so nothing is offered in one place and missing in the other.
///
/// The file is fetched as the bar appears, so `ShareLink` has something real to offer rather
/// than a promise. That is why the viewer shares with a `ShareLink` and the grid asks for a
/// sheet: here there is a view to hang one on and a moment to get the bytes in.
struct LibraryViewerBar: View {
    /// The picture the bar is about.
    let entry: CachedEntry

    @Environment(LibraryCatalog.self) private var catalog
    /// The file on this phone, once it is here.
    @State private var file: URL?

    var body: some View {
        HStack(spacing: 26) {
            Button {
                Task { await catalog.setFavourite([entry.id], on: !entry.isFavourite) }
            } label: {
                Image(systemName: entry.isFavourite ? "star.fill" : "star")
            }
            .disabled(!catalog.isLive(for: entry))
            .accessibilityLabel(entry.isFavourite ? "Remove from Favorites" : "Add to Favorites")

            if let file {
                ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                Button {
                    Task { try? await PhotosSaver.save(file, isVideo: entry.isVideo) }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("Save to Photos")
            }

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
        .task(id: entry.id + entry.version) {
            let lease = await catalog.lease(entry)
            file = try? await catalog.file(for: entry)
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(30)) }
            withExtendedLifetime(lease) {}
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
