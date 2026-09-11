import SwiftUI
import ZephraStyle

/// One picture in the grid: the thumbnail, a star if it is a favorite, a badge if it is a clip
/// or was made larger from another, and the menu every picture in the app wears.
///
/// The thumbnail is fetched in `.task`, which SwiftUI cancels when the cell scrolls away — so
/// a fast flick through a thousand pictures asks the Mac for the handful it stopped on rather
/// than for all of them. The cache answers first, so a picture already seen never asks at all.
struct LibraryCell: View {
    /// The picture this cell shows.
    let entry: CachedEntry

    @Environment(LibraryCatalog.self) private var catalog
    /// The thumbnail's bytes once they are here, or nil while they are not.
    @State private var thumbnail: Data?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { picture }
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
            .task(id: entry.version) { thumbnail = await catalog.thumbnail(for: entry) }
    }

    @ViewBuilder private var picture: some View {
        if let thumbnail, let image = UIImage(data: thumbnail) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(.quaternary)
        }
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
