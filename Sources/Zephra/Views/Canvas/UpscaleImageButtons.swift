import SwiftUI
import ZephraCore
import ZephraEngine

/// The same two buttons as the library's, for the picture on the canvas.
///
/// An upscale reads its parent's record off the disk, so a picture that has not been written yet
/// has nothing to be made larger from: the pair greys until the save lands, which is a second at
/// most and is the same rule Reveal in Finder already follows.
struct UpscaleImageButtons: View {
    /// The picture the buttons act on.
    let image: GeneratedImage

    @Environment(GenerationStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            button(2)
            button(4)
        }
    }

    private func button(_ factor: Int) -> some View {
        Button {
            store.upscale(.image(image), factor: factor)
        } label: {
            Text("Upscale \(factor)\u{00D7}").frame(maxWidth: .infinity)
        }
        .disabled(!store.canUpscale || image.fileURL == nil)
        .help(
            image.fileURL == nil
                ? ImageFacts.notSaved
                : "Write a copy \(factor)\u{00D7} larger into the library")
    }
}

#Preview("Upscale") {
    UpscaleImageButtons(image: PreviewImages.sample())
        .padding(18)
        .frame(width: 320)
        .environment(GenerationStore.preview(state: .ready))
}
