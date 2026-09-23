import SwiftUI
import ZephraCore
import ZephraEngine

/// The one or two lines the well owes under itself: what would not fit, and what will be read
/// over white.
///
/// A modifier rather than a view under the well, so that a well with nothing to say is laid out
/// exactly as it was before there was anything to say at all — a `VStack` around one child with
/// a spacing nobody can see still moves the prompt beside it by those points. With nothing to
/// say this hands the content straight back.
///
/// The transparency line is worked out off the main actor (`ReferenceMatteNote`), because
/// answering it means walking up to ten PNG headers and `body` is not the place for that. The
/// refusal line is the store's own `referenceNote`, already written where the refusal happened.
struct ReferenceNotes: ViewModifier {
    @Environment(GenerationStore.self) private var store
    @State private var matte: String?

    func body(content: Content) -> some View {
        let notes = notes
        VStack(alignment: .trailing, spacing: notes.isEmpty ? 0 : 5) {
            content
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: noteWidth, alignment: .trailing)
            }
        }
        .task(id: key) { await readMatte() }
    }

    /// How wide a note may wrap: the strip's own width for a model that draws one, the single
    /// well's one tile otherwise — never the strip's old fixed three tiles, which said nothing
    /// true about a strip holding one picture or ten.
    private var noteWidth: CGFloat {
        let capabilities = store.descriptor.capabilities
        guard ReferenceStripLayout.drawsStrip(capabilities: capabilities) else {
            return ReferenceStripLayout.tile
        }
        return ReferenceStripLayout(
            pictures: store.settings.referenceImages.count, room: store.referenceRoom
        ).visibleWidth
    }

    private var notes: [String] {
        [store.referenceNote, matte].compactMap { $0 }
    }

    /// What the transparency answer is keyed on: the model, and the pictures by their weights,
    /// which is as good as their bytes for "did the strip change" and costs no hashing.
    private var key: [String] {
        [store.descriptor.id] + store.settings.referenceImages.map { String($0.data.count) }
    }

    private func readMatte() async {
        let pictures = store.settings.referenceImages
        let capabilities = store.descriptor.capabilities
        let name = store.descriptor.fullName
        let answer = await Task.detached(priority: .utility) {
            ReferenceMatteNote.text(for: pictures, capabilities: capabilities, modelName: name)
        }.value
        guard !Task.isCancelled else { return }
        matte = answer
    }
}
