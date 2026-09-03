import SwiftUI
import ZephraEngine

/// The two ways to make the image being looked at larger, side by side at the foot of the
/// library's inspector.
///
/// Two buttons rather than a menu: there are exactly two answers, and a menu would hide both
/// behind a press. They grey together, because what stops one stops the other — a build with no
/// upscaler in it, or an engine already busy with a model.
struct UpscaleButtons: View {
    /// The image the buttons act on.
    let item: LibraryItem

    @Environment(GenerationStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            button(2)
            button(4)
        }
    }

    private func button(_ factor: Int) -> some View {
        Button {
            store.upscale(.file(item.url), factor: factor)
        } label: {
            Text("Upscale \(factor)\u{00D7}").frame(maxWidth: .infinity)
        }
        .disabled(!store.canUpscale)
        .help("Write a copy \(factor)\u{00D7} larger into the library")
    }
}

#Preview("Upscale") {
    UpscaleButtons(item: PreviewImages.library(count: 1).items[0])
        .padding(18)
        .frame(width: 320)
        .environment(GenerationStore.preview(state: .ready))
}
