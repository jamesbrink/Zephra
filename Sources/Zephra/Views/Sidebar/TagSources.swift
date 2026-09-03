import SwiftUI
import ZephraEngine

/// The tags in use, as chips rather than rows.
///
/// Chips because a tag is a word of the user's own choosing and the words are all different
/// lengths: a column of rows would leave most of the sidebar's width empty, and there are
/// usually more tags than there are standing collections. Pressing one narrows whatever scope
/// is showing; pressing it again widens back.
///
/// Absent entirely when nothing is tagged, which is the state a new library is in — an empty
/// heading would be a promise the app has not yet asked anyone to keep.
struct TagSources: View {
    @Environment(LibraryIndex.self) private var index
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        if !index.allTags.isEmpty {
            Section("Tags") {
                WrappingHStack {
                    ForEach(index.allTags, id: \.self) { tag in
                        Button {
                            if workspace.query.tag == tag {
                                workspace.query.tag = nil
                            } else {
                                workspace.show(tag: tag)
                            }
                        } label: {
                            Chip(tag, isSelected: workspace.query.tag == tag)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(tag), \(index.counts.perTag[tag] ?? 0) images")
                        .accessibilityAddTraits(workspace.query.tag == tag ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }
}

#Preview("Tags") {
    List {
        TagSources()
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 160)
    .environment(LibraryIndex.preview(count: 38))
    .environment(WorkspaceSelection(pane: .library))
}
