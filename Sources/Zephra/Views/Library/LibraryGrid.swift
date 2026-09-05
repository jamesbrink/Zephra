import SwiftUI
import ZephraEngine

/// The wall of images, grouped by the day they were made.
///
/// The keyboard is `LibraryGridKeyboard`'s business and the pointer is the cell's. Everything
/// the arrow keys do is worked out by `LibraryCursor`, which is a pure function over the
/// sections and the selection, so "down from the last row of one day lands in the next day at
/// the same column" is a thing that can be tested rather than a thing that is fiddled with.
///
/// The ring around a chosen image is drawn here rather than in the cell: a cell draws one
/// picture, and whether that picture is chosen is a fact about the grid.
struct LibraryGrid: View {
    /// What is selected, shared with the pane that owns it.
    let selection: LibrarySelection

    @Environment(LibraryIndex.self) private var index
    @Environment(\.libraryThumbnails) private var thumbnails

    /// The gap between two cells, and between a day's last row and the next day's heading.
    private static let cellSpacing: CGFloat = 12
    private static let sectionSpacing: CGFloat = 18
    /// The air between the grid and the pane's edges, which the column count allows for.
    private static let horizontalPadding: CGFloat = 20

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if index.sections.isEmpty {
                    LibraryEmptyState()
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    grid
                }
            }
            .background(.background)
            .focusable()
            // The ring the system would draw round the whole pane says nothing; the ring
            // round the selected cell is what shows where the keyboard is.
            .focusEffectDisabled()
            .modifier(LibraryGridKeyboard(selection: selection, proxy: proxy))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                selection.columns = GridColumns.count(
                    width: $0, edge: edge, spacing: Self.cellSpacing, inset: Self.horizontalPadding)
            }
            // Focus-scoped on purpose: it is what tells the menu bar that ⌘A means these
            // images rather than the text in the sidebar's search field.
            .focusedValue(\.focusedLibraryGrid, selection)
            // Plain ⌘C, through the responder chain rather than a second Copy item: the Edit
            // menu's Copy reaches this only while the grid has the keyboard, so Copy in the
            // search field still means the text there. ⇧⌘C stays the named "Copy Image".
            .onCopyCommand { ImageExport.itemProviders(for: selected.map(\.url)) }
            // The grid is torn down while the viewer is up and rebuilt fresh the moment it
            // closes, so a selection left over from stepping through the viewer would
            // otherwise land off screen with nothing to bring it back into view.
            .onAppear { if let id = selection.single { proxy.scrollTo(id, anchor: .center) } }
        }
        .modifier(LibraryOpenCommand(selection: selection))
        .modifier(LibraryQuickLook(selection: selection))
        .modifier(LibraryDeleteCommand(selection: selection))
        .onChange(of: index.sections) { selection.keeping(shown) }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: edge, maximum: .infinity), spacing: Self.cellSpacing)],
            alignment: .leading,
            spacing: Self.sectionSpacing
        ) {
            ForEach(Array(index.sections.enumerated()), id: \.element.id) { offset, section in
                Section {
                    ForEach(section.items) { item in cell(item) }
                } header: {
                    LibraryDayHeader(section: section)
                } footer: {
                    LibraryLookAhead(items: lookAhead(after: offset))
                }
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.sectionSpacing)
    }

    private func cell(_ item: LibraryItem) -> some View {
        LibraryCell(item: item) { modifiers in click(item, modifiers) }
            .id(item.id)
            .overlay {
                if selection.contains(item.id) {
                    RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius + 1, style: .continuous)
                        .inset(by: -1)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .accessibilityAddTraits(selection.contains(item.id) ? .isSelected : [])
            .contextMenu { LibraryItemMenu(items: targets(for: item), selection: selection) }
    }

    /// What a click does, which depends entirely on what was held down while it happened.
    private func click(_ item: LibraryItem, _ modifiers: LibraryCursor.ClickModifiers) {
        selection.apply(LibraryCursor.click(
            item.id,
            in: index.sections,
            modifiers: modifiers,
            selection: selection.ids,
            anchor: selection.anchor
        ))
    }

    /// What a menu opened over one image should act on: the whole selection when that image is
    /// part of it, and only that image when it is not.
    private func targets(for item: LibraryItem) -> [LibraryItem] {
        selection.contains(item.id) ? selected : [item]
    }

    /// The images just below the fold of one section, for the cache to get a head start on.
    private func lookAhead(after offset: Int) -> [LibraryItem] {
        let following = index.sections.dropFirst(offset + 1).flatMap(\.items)
        return Array(following.prefix(max(selection.columns, 1) * 3))
    }

    private var edge: CGFloat { thumbnails?.edge ?? CGFloat(AppSettings.initialLibraryThumbnailEdge) }

    /// The selected images in the order the grid shows them.
    private var selected: [LibraryItem] {
        index.sections.flatMap { $0.items.filter { selection.contains($0.id) } }
    }

    private var shown: Set<LibraryItem.ID> {
        Set(index.sections.flatMap { $0.items.map(\.id) })
    }
}

#Preview("Grid") {
    LibraryGrid(selection: LibrarySelection())
        .frame(width: 900, height: 700)
        .environment(\.libraryThumbnails, LibraryThumbnails(cache: ThumbnailCache(), edge: 168))
        .environment(PreviewImages.library(count: 38))
        .environment(WorkspaceSelection(pane: .library))
        .environment(GenerationStore.preview(state: .ready))
}
