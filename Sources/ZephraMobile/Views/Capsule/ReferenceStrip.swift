import SwiftUI
import ZephraCore
import ZephraLinkProtocol

/// The well when the model reads several pictures: a row of tiles in the order the model reads
/// them, with a place to add one at the end.
///
/// The order is a choice rather than a presentation, so it can be changed: a tile is dragged
/// onto the place it should take and the rest close up behind it. The drag carries the tile's
/// position as text, which is all one row of one app needs; a drop that is not a position this
/// strip has moves nothing, so a word dropped from another app is ignored rather than obeyed.
///
/// Drawn only where `ModelCapabilities.acceptsSeveralReferences` holds. Every other model keeps
/// the single well it has always had, which is `ReferenceWell`'s other branch.
struct ReferenceStrip: View {
    /// What the model in force will accept, which says how many tiles there is room for.
    let capabilities: CapabilitiesSummary
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(Array(draft.references.enumerated()), id: \.offset) { index, picture in
                    ReferenceSlotView(picture: picture) { draft.removeReference(at: index) }
                        .draggable(String(index)) { ReferenceSlotView(picture: picture) }
                        .dropDestination(for: String.self) { items, _ in
                            move(items, onto: index)
                        }
                }
                if draft.referenceRoom(for: capabilities.capabilities) > 0 {
                    ReferenceLibraryButton(
                        asTile: true, room: draft.referenceRoom(for: capabilities.capabilities))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .frame(height: 78)
        .accessibilityLabel(
            ReferenceRole(capabilities: capabilities.capabilities)
                .filledWellAccessibilityLabel(count: draft.references.count))
    }

    /// Puts the dragged tile in `index`'s place. A drop of anything that is not one of this
    /// strip's own positions changes nothing and says so, so the picture goes back where it was.
    private func move(_ items: [String], onto index: Int) -> Bool {
        guard let text = items.first, let from = Int(text),
            draft.references.indices.contains(from), from != index
        else { return false }
        draft.moveReferences(fromOffsets: [from], toOffset: index > from ? index + 1 : index)
        return true
    }
}
