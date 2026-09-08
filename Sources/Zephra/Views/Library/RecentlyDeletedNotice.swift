import SwiftUI
import ZephraEngine

/// The strip that appears only inside Recently Deleted: how long the images have, and the two
/// ways out of it.
///
/// It says the thirty days rather than leaving them to be discovered, because the whole point
/// of the folder is that it is not the end — and somebody who does not know that will empty it
/// by hand out of tidiness.
struct RecentlyDeletedNotice: View {
    /// What is selected in the grid, which is what the buttons act on.
    let selection: LibrarySelection

    @Environment(LibraryIndex.self) private var index

    var body: some View {
        if index.query.scope == .recentlyDeleted {
            HStack(spacing: 10) {
                Label("Images stay here for 30 days", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Button("Put Back") { index.restore(selection.ids) }
                    Button("Delete Permanently", role: .destructive) { Task { await index.delete(selection.ids) } }
                }
                .controlSize(.small)
                .disabled(selection.ids.isEmpty)
            }
            .padding(.horizontal, 20)
            .frame(height: 36)
            .background(.bar)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ZephraChrome.hairline)
                    .frame(height: 1)
            }
        }
    }
}

#Preview("Recently deleted") {
    let index = PreviewImages.library(count: 8)
    index.query = LibraryQuery(scope: .recentlyDeleted)
    return RecentlyDeletedNotice(selection: LibrarySelection())
        .frame(width: 820)
        .environment(index)
}
