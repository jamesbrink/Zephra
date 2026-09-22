import SwiftUI
import ZephraEngine
import ZephraStyle

/// Every image in the library, narrowed only by the sheet's own search text — scope `.all`,
/// newest first, the same order the library grid defaults to — in cells of at least 120 pt
/// that share the row's width, so the gaps are the one 10 pt everywhere rather than the
/// leftover the adaptive grid would otherwise spread between fixed squares.
///
/// Clicking a cell chooses it, command-clicking adds or removes one, shift-clicking takes the
/// run between the anchor and it, and the arrow keys do the same through
/// `ReferencePickerKeyboard`; a second click, or Return from the sheet's own "Use" button,
/// confirms. On a model that reads one picture the modifiers do nothing and the sheet behaves
/// exactly as it always has. The double-tap gesture is declared first for the same reason
/// `LibraryCell`'s is: SwiftUI offers a tap to whichever gesture was attached first, so a
/// single-tap handler written before the double-tap one would swallow the first half of every
/// double-click.
struct ReferencePickerGrid: View {
    /// What is typed, and what is chosen so far.
    let selection: ReferencePickerSelection
    /// What a double-click on a cell does with the images picked.
    let confirm: ([LibraryItem]) -> Void

    @Environment(LibraryIndex.self) private var index

    private static let edge: CGFloat = 120
    private static let spacing: CGFloat = 10
    private static let inset: CGFloat = 12

    var body: some View {
        let matches = matches
        ScrollViewReader { proxy in
            ScrollView {
                if matches.isEmpty {
                    ContentUnavailableView.search(text: selection.text)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Self.edge, maximum: .infinity), spacing: Self.spacing)],
                        spacing: Self.spacing
                    ) {
                        ForEach(matches) { item in cell(item, in: matches) }
                    }
                    .padding(Self.inset)
                }
            }
            .modifier(ReferencePickerKeyboard(selection: selection, matches: matches))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                selection.columns = GridColumns.count(
                    width: $0, edge: Self.edge, spacing: Self.spacing, inset: Self.inset)
            }
            // An arrow key can pick a cell that has scrolled away; a click cannot, and a
            // scroll to what is already on screen moves nothing.
            .onChange(of: selection.anchor) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .modifier(ReferencePickerThumbnails())
        // A pick that is no longer on screen is no pick — hidden by the search, or gone from
        // the folder while the sheet was up: Use would otherwise adopt a picture that is not
        // there. Keyed on the ids shown, so either way of losing it is noticed.
        .onChange(of: matches.map(\.id)) { selection.prune(to: matches) }
    }

    private func cell(_ item: LibraryItem, in matches: [LibraryItem]) -> some View {
        let isPicked = selection.ids.contains(item.id)
        return LibraryThumbnail(item: item)
            .id(item.id)
            .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous))
            .overlay {
                if isPicked {
                    RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius + 1, style: .continuous)
                        .inset(by: -1)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            // A double-click means this picture and only this one, whatever was picked before:
            // it is the shortcut for "that one, now", and confirming a selection the second
            // click was not part of would adopt pictures nobody pointed at.
            .onTapGesture(count: 2) {
                selection.click(item.id, in: matches, modifiers: [])
                confirm([item])
            }
            .onTapGesture(count: 1) {
                selection.click(item.id, in: matches, modifiers: .current)
            }
            .accessibilityLabel(item.prompt.isEmpty ? item.fileName : item.prompt)
            .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
    }

    /// Everything made here and everything imported to start from, newest first, matched on
    /// the text alone: a picture is picked here by what it looks like, not by which collection
    /// the sidebar happens to be narrowed to. Only Recently Deleted is left out.
    private var matches: [LibraryItem] {
        let made = LibraryQuery(text: selection.text, sort: .newestFirst).matching(index.items)
        let imported = LibraryQuery(scope: .sources, text: selection.text, sort: .newestFirst)
            .matching(index.items)
        return (made + imported).sorted { $0.createdAt > $1.createdAt }
    }
}

#Preview("Grid") {
    ReferencePickerGrid(selection: ReferencePickerSelection(limit: 10)) { _ in }
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
