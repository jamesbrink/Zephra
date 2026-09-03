import SwiftUI

/// Pinned to the foot of the library sidebar, under Recently Deleted: the way to make an album.
///
/// At the foot rather than as a link in the Albums heading, which is where it used to be. A
/// heading's link is a word the eye slides off, it moves down the sidebar as models and tags
/// come and go, and it is nowhere near the list it adds to once that list is long enough to
/// scroll. A bar pinned to the bottom edge is always in the same place, is the shape every Mac
/// sidebar puts its add button in, and is a target rather than a word.
///
/// It does not know how to make an album. `SidebarView` does, because ⌘N has to make one too and
/// two copies of "make it, show it, start naming it" is one copy too many.
struct NewAlbumBar: View {
    /// What pressing it does.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New Album", systemImage: "plus.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .help("Make a new album")
    }
}

#Preview("New album") {
    NewAlbumBar {}
        .frame(width: 280)
}
