import SwiftUI
import ZephraStyle

/// One picture full size, with the rest of its day a swipe away.
///
/// A paged `TabView` rather than a navigation push, because swiping between pictures is what a
/// phone's photo viewer *is*; the day is what it pages through, for the reason `LibraryScreen`
/// gives. A clip plays in place through AVKit rather than showing its poster: the poster is
/// how a clip is filed, not how it is watched.
struct LibraryViewer: View {
    /// The day's pictures, in the order the grid showed them.
    let entries: [CachedEntry]
    /// Which one is on screen.
    @State private var current: String

    /// Opens the day at one picture.
    init(entries: [CachedEntry], opening fileName: String) {
        self.entries = entries
        _current = State(initialValue: fileName)
    }

    var body: some View {
        TabView(selection: $current) {
            ForEach(entries) { entry in
                ViewerPicture(entry: entry)
                    .tag(entry.fileName)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(.black)
        .overlay(alignment: .top) { LibraryViewerTitle(entry: shown, of: entries.count) }
        .overlay(alignment: .bottom) {
            if let shown { LibraryViewerBar(entry: shown) }
        }
        .modifier(LibraryRequests())
        .statusBarHidden()
    }

    /// The picture on screen, or nil once the last one in the day has been deleted.
    private var shown: CachedEntry? {
        entries.first { $0.fileName == current } ?? entries.first
    }
}

/// The strip across the top: where in the day this is, and the way out.
///
/// Its own view so the viewer holds two stored properties rather than four, and so the way out
/// is one file — the one thing in here that has nothing to do with pictures.
private struct LibraryViewerTitle: View {
    let entry: CachedEntry?
    let of: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(MobileChrome.viewerChromeOpacity))
            }
            .accessibilityLabel("Close")
            Spacer(minLength: 0)
            if let entry {
                Text(entry.label)
                    .font(.footnote)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(ZephraChrome.shadowOpacity), radius: 4)
            }
        }
        .padding(.horizontal, MobileChrome.sideMargin)
        .padding(.top, 8)
    }
}

#Preview("Viewer") {
    LibraryViewer(
        entries: MobilePreview.library().map(CachedEntry.init),
        opening: MobilePreview.library()[0].fileName
    )
    .environment(LibraryCatalog(libraryRoot: nil, filesRoot: nil))
    .environment(ReferenceIntent())
    .environment(MobileSelection())
}
