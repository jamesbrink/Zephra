import SwiftUI
import ZephraStyle

/// The Mac's library, as a grid to pick a reference picture out of.
///
/// Deliberately plain: thumbnails, newest first. It draws `LibraryCatalog` rather than a
/// library of its own, so it shows what the Library tab shows, works with no Mac in reach, and
/// costs nothing for a picture already looked at — the squares are the grid's own
/// `EntryThumbnail`.
///
/// Picking says a **name**, through `ReferenceIntent`, exactly as the library's "Use as
/// Reference" does. One path from a name to the picture in the well, ending at
/// `ReferenceIntentReader` on the canvas; a second door that fetched and adopted for itself
/// would be a second set of rules to keep in step.
struct ReferencePickerSheet: View {
    @Environment(LibraryCatalog.self) private var catalog
    @Environment(ReferenceIntent.self) private var reference
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(catalog.entries) { entry in
                        Button {
                            reference.use(entry.fileName)
                            dismiss()
                        } label: {
                            EntryThumbnail(entry: entry)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: ZephraChrome.thumbnailRadius,
                                        style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(entry.label)
                    }
                }
                .padding(MobileChrome.sideMargin)
            }
            .background(Color.canvasBackground)
            .navigationTitle("Choose a Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
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

    private static let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]
}
