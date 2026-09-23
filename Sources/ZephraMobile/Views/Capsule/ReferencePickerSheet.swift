import SwiftUI
import ZephraStyle

/// The Mac's library, as a grid to pick reference pictures out of.
///
/// Deliberately plain: thumbnails, newest first. It draws `LibraryCatalog` rather than a
/// library of its own, so it shows what the Library tab shows, works with no Mac in reach, and
/// costs nothing for a picture already looked at — the squares are the grid's own
/// `EntryThumbnail`.
///
/// Picking says **names**, through `ReferenceIntent`, exactly as the library's "Use as
/// Reference" does. One path from a name to the picture in the well, ending at
/// `ReferenceIntentReader` on the canvas; a second door that fetched and adopted for itself
/// would be a second set of rules to keep in step.
///
/// A tap marks a picture and the toolbar's button is what sends them, whether it is one picture
/// or five: a well that takes several has to let somebody change their mind before the sheet
/// goes, and one rule for both is a rule that cannot come to differ.
struct ReferencePickerSheet: View {
    /// How many more pictures the well would take.
    let room: Int
    @State private var selection: [String] = []
    @Environment(LibraryCatalog.self) private var catalog

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(catalog.entries) { entry in
                        Button { choose(entry.id) } label: { cell(entry) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(MobileChrome.sideMargin)
            }
            .background(Color.canvasBackground)
            .navigationTitle(room > 1 ? "Choose Pictures" : "Choose a Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissSheetButton(title: "Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    ReferencePickerConfirm(selection: $selection)
                }
            }
            .overlay {
                if catalog.entries.isEmpty {
                    ContentUnavailableView(
                        "No pictures yet", systemImage: "square.grid.2x2",
                        description: Text("Your Mac's library appears here."))
                }
            }
        }
    }

    /// One square, marked when it is one of the ones going.
    private func cell(_ entry: CachedEntry) -> some View {
        EntryThumbnail(entry: entry)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                LibraryHostLabel(entry: entry).padding(4).allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                if let place = selection.firstIndex(of: entry.id) {
                    Image(systemName: "\(place + 1).circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(4)
                }
            }
            .accessibilityElement(children: .ignore)
            .modifier(LibraryOwnershipAccessibility(entry: entry))
    }

    /// Marks a picture, or unmarks one already marked. Where the well holds one, a second tap
    /// on another picture is a change of mind rather than a second picture.
    private func choose(_ id: String) {
        if let place = selection.firstIndex(of: id) {
            selection.remove(at: place)
        } else if room > 1 {
            guard selection.count < room else { return }
            selection.append(id)
        } else {
            selection = [id]
        }
    }

    private static let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]
}
