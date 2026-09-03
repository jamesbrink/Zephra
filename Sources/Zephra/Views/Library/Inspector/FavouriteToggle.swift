import SwiftUI
import ZephraEngine

/// The star. Filled when every image it stands for is a favourite, hollow otherwise.
///
/// A mixed selection reads as not-favourite and one press makes it agree, which is what
/// `toggleFavourite` does: a toggle over several things should settle them, not invert each of
/// them separately and leave the set exactly as mixed as it was.
struct FavouriteToggle: View {
    /// The images the star acts on.
    let ids: Set<LibraryItem.ID>

    @Environment(LibraryIndex.self) private var index

    var body: some View {
        Button {
            index.toggleFavourite(ids)
        } label: {
            Image(systemName: isFavourite ? "star.fill" : "star")
                .foregroundStyle(isFavourite ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .disabled(ids.isEmpty)
        .help(isFavourite ? "Remove from favourites" : "Add to favourites")
        .accessibilityLabel(isFavourite ? "Remove from favourites" : "Add to favourites")
    }

    private var isFavourite: Bool {
        !ids.isEmpty && ids.allSatisfy { index.item(for: $0)?.isFavourite == true }
    }
}

#Preview("Star") {
    let index = LibraryIndex.preview(count: 8)
    return HStack(spacing: 20) {
        FavouriteToggle(ids: [index.items[0].id])
        FavouriteToggle(ids: [index.items[1].id])
    }
    .font(.title3)
    .padding(24)
    .environment(index)
}
