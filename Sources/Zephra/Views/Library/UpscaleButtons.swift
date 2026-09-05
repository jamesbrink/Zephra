import SwiftUI
import ZephraCore
import ZephraEngine

/// The two ways to make a picture larger, side by side at the foot of an inspector.
///
/// Two buttons rather than a menu: there are exactly two answers, and a menu would hide both
/// behind a press. They grey together, because what stops one stops the other — a build with no
/// upscaler in it, an engine already busy with a model, or a picture that is not on the disk
/// yet: an upscale reads its parent's record off the disk, so the canvas hands over
/// `unsavedReason` until the save lands, which is a second at most and is the same rule Reveal
/// in Finder already follows. The library's pictures are always saved and pass nothing.
struct UpscaleButtons: View {
    /// The picture the buttons act on.
    let source: UpscaleSource
    /// Why the picture cannot be upscaled yet, shown in place of the help; nil enables them.
    let unsavedReason: String?

    @Environment(GenerationStore.self) private var store

    init(source: UpscaleSource, unsavedReason: String? = nil) {
        self.source = source
        self.unsavedReason = unsavedReason
    }

    var body: some View {
        HStack(spacing: 8) {
            button(2)
            button(4)
        }
    }

    private func button(_ factor: Int) -> some View {
        Button {
            store.upscale(source, factor: factor)
        } label: {
            Text("Upscale \(factor)\u{00D7}").frame(maxWidth: .infinity)
        }
        .disabled(!store.canUpscale || unsavedReason != nil)
        .help(unsavedReason ?? "Write a copy \(factor)\u{00D7} larger into the library")
    }
}

#Preview("Upscale") {
    UpscaleButtons(source: .file(PreviewImages.library(count: 1).items[0].url))
        .padding(18)
        .frame(width: 320)
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("Not saved yet") {
    UpscaleButtons(source: .image(PreviewImages.sample()), unsavedReason: ImageFacts.notSaved)
        .padding(18)
        .frame(width: 320)
        .environment(GenerationStore.preview(state: .ready))
}
