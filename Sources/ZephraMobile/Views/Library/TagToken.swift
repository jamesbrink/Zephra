import SwiftUI
import ZephraStyle

/// One tag, as a token.
///
/// `Chip`'s shape from the shared chrome, so a tag on the phone and a tag on the Mac are the
/// same thing to look at. The cross appears only on a token that can be taken off, which is
/// what tells the two lists in the tag sheet apart without a word of explanation.
struct TagToken: View {
    /// The tag.
    let title: String
    /// What to do when its cross is pressed, or nil for one that is only offered.
    var onRemove: (() -> Void)?

    var body: some View {
        Chip(title, isSelected: onRemove != nil, onRemove: onRemove)
    }
}

#Preview("Tokens") {
    VStack(alignment: .leading, spacing: 8) {
        TagToken(title: "rain")
        TagToken(title: "harbour") {}
    }
    .padding(24)
}
