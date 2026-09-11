import SwiftUI
import ZephraStyle

/// One picture in the grid: the thumbnail, a star if it is a favorite, a badge if it is a clip
/// or was made larger from another, and the menu every picture in the app wears.
///
/// The square itself is `EntryThumbnail`, which every grid on the phone draws, so what a
/// picture looks like while its bytes are coming is decided in one place and a picture fetched
/// here is on the phone for the reference picker too.
struct LibraryCell: View {
    /// The picture this cell shows.
    let entry: CachedEntry

    var body: some View {
        EntryThumbnail(entry: entry)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(
                RoundedRectangle(cornerRadius: ZephraChrome.tileRadius, style: .continuous)
            )
            .overlay(alignment: .bottomTrailing) { favourite }
            .overlay(alignment: .topLeading) { badge }
            .contentShape(Rectangle())
            .contextMenu { LibraryItemMenu(entry: entry) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.label)
            .accessibilityAddTraits(.isButton)
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
