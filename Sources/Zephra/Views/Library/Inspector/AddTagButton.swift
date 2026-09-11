import SwiftUI
import ZephraStyle

/// The dashed chip at the end of the tags, which opens the popover that adds one.
///
/// Dashed rather than filled because it is not a tag: it is the space where one would go, and
/// the outline is what says so without a word.
struct AddTagButton: View {
    /// The images a new tag would go on.
    let ids: Set<LibraryItem.ID>

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Text(verbatim: "\u{FF0B} tag")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .overlay {
                    RoundedRectangle(cornerRadius: ZephraChrome.chipRadius, style: .continuous)
                        .strokeBorder(
                            ZephraChrome.hairline,
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a tag")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            TagPopover(ids: ids)
        }
    }
}
