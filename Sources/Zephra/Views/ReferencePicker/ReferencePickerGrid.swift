import SwiftUI
import ZephraEngine

/// Every image in the library, narrowed only by the sheet's own search text — scope `.all`,
/// newest first, the same order the library grid defaults to — laid out at a fixed 120 pt so
/// the picker never grows or shrinks the way the library's own slider does.
///
/// Clicking a cell chooses it; a second click, or Return from the sheet's own "Use" button,
/// confirms it. The double-tap gesture is declared first for the same reason `LibraryCell`'s
/// is: SwiftUI offers a tap to whichever gesture was attached first, so a single-tap handler
/// written before the double-tap one would swallow the first half of every double-click.
struct ReferencePickerGrid: View {
    /// What is typed, and what is chosen so far.
    let selection: ReferencePickerSelection
    /// What a double-click on a cell does with the image under it.
    let confirm: (LibraryItem) -> Void

    @Environment(LibraryIndex.self) private var index

    private static let edge: CGFloat = 120

    var body: some View {
        ScrollView {
            if matches.isEmpty {
                ContentUnavailableView.search(text: selection.text)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Self.edge, maximum: .infinity), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(matches) { item in cell(item) }
                }
                .padding(12)
            }
        }
        .modifier(ReferencePickerThumbnails())
        // A pick the search has since hidden is no pick: Use would otherwise adopt a picture
        // that is not on screen.
        .onChange(of: selection.text) {
            guard let picked = selection.item, !matches.contains(where: { $0.id == picked.id })
            else { return }
            selection.item = nil
        }
    }

    private func cell(_ item: LibraryItem) -> some View {
        LibraryThumbnail(item: item)
            .frame(width: Self.edge, height: Self.edge)
            .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous))
            .overlay {
                if selection.item?.id == item.id {
                    RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius + 1, style: .continuous)
                        .inset(by: -1)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { confirm(item) }
            .onTapGesture(count: 1) { selection.item = item }
            .accessibilityLabel(item.prompt.isEmpty ? item.fileName : item.prompt)
            .accessibilityAddTraits(.isButton)
    }

    /// `.all`, unfiltered by scope or model or tag: a picture is picked here by what it looks
    /// like, not by which collection the sidebar happens to be narrowed to.
    private var matches: [LibraryItem] {
        LibraryQuery(text: selection.text, sort: .newestFirst).matching(index.items)
    }
}

#Preview("Grid") {
    ReferencePickerGrid(selection: ReferencePickerSelection()) { _ in }
        .frame(width: 640, height: 420)
        .environment(PreviewImages.library(count: 24))
        .environment(ThumbnailCache())
}

#Preview("No matches") {
    let selection = ReferencePickerSelection()
    selection.text = "nothing matches this"
    return ReferencePickerGrid(selection: selection) { _ in }
        .frame(width: 640, height: 420)
        .environment(PreviewImages.library(count: 24))
        .environment(ThumbnailCache())
}
