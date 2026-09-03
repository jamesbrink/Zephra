import SwiftUI
import ZephraEngine

/// Where a tag is typed or picked, hanging off the plus beside the chips.
///
/// A field with suggestions under it rather than a token field, which SwiftUI has not got. The
/// suggestions are the tags already in use, filtered as you type, so a library does not end up
/// with "night", "Night" and "nights" meaning the same thing through nobody's fault.
struct TagPopover: View {
    /// The images the tag goes on.
    let ids: Set<LibraryItem.ID>

    @Environment(LibraryIndex.self) private var index
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Tag", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { add(text) }
            if !suggestions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(suggestions, id: \.self) { tag in
                        Button(tag) { add(tag) }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    /// Tags in use that this could still become, minus the ones every chosen image already has.
    private var suggestions: [String] {
        let typed = LibraryItem.folded(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return index.allTags
            .filter { tag in
                guard !ids.allSatisfy({ index.item(for: $0)?.tags.contains(tag) == true }) else {
                    return false
                }
                return typed.isEmpty || LibraryItem.folded(tag).contains(typed)
            }
            .prefix(6)
            .map { $0 }
    }

    private func add(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        index.addTag(trimmed, to: ids)
        text = ""
    }
}

#Preview("Tag popover") {
    let index = LibraryIndex.preview(count: 12)
    return TagPopover(ids: [index.items[1].id])
        .environment(index)
}
