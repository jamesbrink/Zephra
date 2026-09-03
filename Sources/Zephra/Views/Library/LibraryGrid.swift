import AppKit
import SwiftUI
import ZephraEngine

/// The wall of images, grouped by the day they were made.
///
/// The keyboard is the grid's own business and the pointer is the cell's. Everything the arrow
/// keys do is worked out by `LibraryCursor`, which is a pure function over the sections and the
/// selection, so "down from the last row of one day lands in the next day at the same column"
/// is a thing that can be tested rather than a thing that is fiddled with here.
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
            .focusEffectDisabled()
            .onMoveCommand { move($0, revealing: proxy) }
            .onGeometryChange(for: Int.self) { columns(across: $0.size.width) } action: {
                selection.columns = $0
            }
            // Focus-scoped on purpose: it is what tells the menu bar that ⌘A means these
            // images rather than the text in the sidebar's search field.
            .focusedValue(\.focusedLibraryGrid, selection)
        }
        .modifier(LibraryOpenCommand(selection: selection))
        .modifier(LibraryQuickLook(selection: selection))
        .modifier(LibraryDeleteCommand(selection: selection))
        .focusedSceneValue(\.libraryIndex, index)
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
        .padding(.horizontal, 20)
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

    /// Shift held during an arrow key means the selection grows from wherever it is anchored,
    /// which is the same rule a shift-click follows.
    private func move(_ direction: MoveCommandDirection, revealing proxy: ScrollViewProxy) {
        guard let heading = LibraryGrid.direction(of: direction),
              let outcome = LibraryCursor.move(
                  heading,
                  in: index.sections,
                  columns: selection.columns,
                  selection: selection.ids,
                  anchor: selection.anchor,
                  extending: NSEvent.modifierFlags.contains(.shift)
              )
        else { return }
        selection.apply(outcome)
        guard let reveal = outcome.reveal else { return }
        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(reveal, anchor: .center) }
    }

    /// What a menu opened over one image should act on: the whole selection when that image is
    /// part of it, and only that image when it is not.
    private func targets(for item: LibraryItem) -> [LibraryItem] {
        guard selection.contains(item.id) else { return [item] }
        return index.sections.flatMap { $0.items.filter { selection.contains($0.id) } }
    }

    /// The images just below the fold of one section, for the cache to get a head start on.
    private func lookAhead(after offset: Int) -> [LibraryItem] {
        let following = index.sections.dropFirst(offset + 1).flatMap(\.items)
        return Array(following.prefix(max(selection.columns, 1) * 3))
    }

    /// How many cells the adaptive grid is fitting across, which is what up and down move by.
    private func columns(across width: CGFloat) -> Int {
        let usable = width - 40 + Self.cellSpacing
        return max(1, Int(usable / (edge + Self.cellSpacing)))
    }

    private var edge: CGFloat { thumbnails?.edge ?? CGFloat(AppSettings.initialLibraryThumbnailEdge) }

    private var shown: Set<LibraryItem.ID> {
        Set(index.sections.flatMap { $0.items.map(\.id) })
    }

    private static func direction(of command: MoveCommandDirection) -> LibraryCursor.Direction? {
        switch command {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        @unknown default: nil
        }
    }
}

#Preview("Grid") {
    LibraryGrid(selection: LibrarySelection())
        .frame(width: 900, height: 700)
        .environment(\.libraryThumbnails, LibraryThumbnails(cache: ThumbnailCache(), edge: 168))
        .environment(LibraryIndex.preview(count: 38))
        .environment(WorkspaceSelection(pane: .library))
        .environment(GenerationStore.preview(state: .ready))
}
