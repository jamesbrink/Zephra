import SwiftUI
import ZephraEngine

/// Today's images, small, in the sidebar, on the canvas pane only.
///
/// It is the way back. A canvas shows one picture, and the one you want is often the one from
/// twenty minutes ago; four thumbnails and a link are enough to get there without leaving the
/// pane you are working in. The library pane shows the same images at a size worth looking at,
/// so this section is not drawn there.
struct TodaySection: View {
    @Environment(LibraryIndex.self) private var index
    @Environment(WorkspaceSelection.self) private var workspace

    /// How many fit in the sidebar's width at two columns without pushing everything below it
    /// off the bottom.
    private static let shown = 4

    var body: some View {
        if !today.isEmpty {
            Section {
                TodayGrid(items: Array(today.prefix(Self.shown)))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if today.count > Self.shown {
                    Button("Show all \(today.count) in Library") {
                        workspace.show(scope: .all)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } header: {
                SectionHeader("Today", detail: "\(today.count)")
            }
        }
    }

    /// The images made today, newest first, which is the order the index already holds them in.
    private var today: [LibraryItem] {
        let calendar = Calendar.current
        return index.items.filter {
            $0.collection == .generated && calendar.isDateInToday($0.createdAt)
        }
    }
}

#Preview("Today") {
    List {
        TodaySection()
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 220)
    .environment(PreviewImages.library(count: 38))
    .environment(WorkspaceSelection(pane: .canvas))
    .environment(ThumbnailCache())
    .environment(GenerationStore.preview(state: .ready))
}
