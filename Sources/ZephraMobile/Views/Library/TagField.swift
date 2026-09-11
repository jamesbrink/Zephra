import SwiftUI

/// The tags on one picture: the ones it has as tokens, and a line to type another.
///
/// Return adds what was typed and leaves the field ready for the next one, which is how
/// anybody typing three tags expects it to go. A word already on the picture is not added
/// twice, and a blank one is not added at all — so nobody can leave a picture carrying an
/// empty tag that matches every search.
struct TagField: View {
    /// The list being edited.
    @Binding var tags: [String]
    /// What is being typed right now.
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty {
                TagFlow(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        TagToken(title: tag) { tags.removeAll { $0 == tag } }
                    }
                }
            }
            TextField("Add a tag", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(add)
        }
        .padding(.vertical, 4)
    }

    /// Takes what was typed, if it is a word and a new one.
    private func add() {
        let tag = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
    }
}

#Preview("Tags") {
    @Previewable @State var tags = ["rain", "harbour"]
    return Form { TagField(tags: $tags) }
}
