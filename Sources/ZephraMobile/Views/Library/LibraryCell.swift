import SwiftUI
import ZephraStyle

/// One picture in the grid: the thumbnail, a star if it is a favorite, a badge if it is a clip
/// or was made larger from another, and the menu every picture in the app wears.
///
/// The square itself is `EntryThumbnail`, which every grid on the phone draws, so what a
/// picture looks like while its bytes are coming is decided in one place and a picture fetched
/// here is on the phone for the reference picker too.
///
/// Where a viewer opens over it, the cell is what the viewer zooms out of and back into. The
/// id it answers to is `ViewerOpening.sourceID(forCell:)`'s, so the cell of the picture the
/// viewer has paged to is the one the zoom back finds; where no viewer opens, it declares no
/// source at all.
struct LibraryCell: View {
    /// The picture this cell shows.
    let entry: CachedEntry

    @Environment(\.viewerOpening) private var opening
    @Environment(\.viewerNamespace) private var namespace

    var body: some View {
        if let namespace, let sourceID {
            square.matchedTransitionSource(id: sourceID, in: namespace) { $0.clipShape(tile) }
        } else {
            square
        }
    }

    private var square: some View {
        EntryThumbnail(entry: entry)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(tile)
            .overlay(alignment: .bottomLeading) { LibraryHostLabel(entry: entry).padding(4).padding(.trailing, 18) }
            .overlay(alignment: .bottomTrailing) { favourite }
            .overlay(alignment: .topLeading) { badge }
            .contentShape(Rectangle())
            .contextMenu { LibraryItemMenu(entry: entry) }
            .accessibilityElement(children: .ignore)
            .modifier(LibraryOwnershipAccessibility(entry: entry))
            .accessibilityAddTraits(.isButton)
    }

    /// The id the zoom transition finds this cell by: its own name while no viewer is up, so
    /// a tap zooms out of here; while one is, `ViewerOpening`'s answer, which is a name for
    /// the cell of the picture on screen and nothing for every other.
    private var sourceID: String? {
        guard let opening else { return entry.id }
        return opening.sourceID(forCell: entry.id)
    }

    private var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: ZephraChrome.tileRadius, style: .continuous)
    }

    @ViewBuilder private var favourite: some View {
        if entry.isFavourite {
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(ZephraChrome.badgeForeground)
                .shadow(color: .black.opacity(ZephraChrome.shadowOpacity), radius: 3, y: 1)
                .padding(5)
        }
    }

    @ViewBuilder private var badge: some View {
        if let factor = entry.upscaleFactor {
            UpscaleBadge(factor: factor)
        } else if let seconds = entry.videoSeconds {
            VideoBadge(seconds: seconds)
        }
    }
}

#Preview("Cell") {
    LibraryCell(entry: CachedEntry(MobilePreview.library()[0]))
        .frame(width: 128, height: 128)
        .environment(LibraryCatalog(libraryRoot: nil, filesRoot: nil))
}
