import SwiftUI
import ZephraEngine

/// The tags on the images being looked at, each removable, and a dashed chip to add one.
///
/// Over a selection, `tags` is the tags every image in it carries, because a chip with a cross
/// on it says "these images have this, press to take it away" — and taking away something only
/// half of them had would be doing two different things at once.
struct TagChips: View {
    /// The images the chips act on.
    let ids: Set<LibraryItem.ID>
    /// The tags to show, already reduced to what the images agree on.
    let tags: [String]

    @Environment(LibraryIndex.self) private var index

    var body: some View {
        WrappingHStack {
            ForEach(tags, id: \.self) { tag in
                Chip(tag) { index.removeTag(tag, from: ids) }
            }
            AddTagButton(ids: ids)
        }
    }
}

#Preview("Tags") {
    let index = LibraryIndex.preview(count: 12)
    let item = index.items[1]
    return TagChips(ids: [item.id], tags: item.tags)
        .padding(18)
        .frame(width: 300)
        .environment(index)
}
