import SwiftUI
import ZephraEngine

/// The two upscale items in an image's context menu.
///
/// Their own view rather than more lines in `LibraryItemMenu`, which already holds its three
/// stored properties and would need the store as a fourth.
///
/// One image at a time in this version: upscaling a whole selection is a queue of its own, and
/// there is no queue for post-processes yet.
struct UpscaleMenuItems: View {
    /// The image the items act on.
    let item: LibraryItem
    /// Whether exactly one image was chosen, which is the only case these offer.
    let isAlone: Bool

    @Environment(GenerationStore.self) private var store

    var body: some View {
        Button("Upscale 2\u{00D7}") { store.upscale(.file(item.url), factor: 2) }
            .disabled(!isAlone || !store.canUpscale)
        Button("Upscale 4\u{00D7}") { store.upscale(.file(item.url), factor: 4) }
            .disabled(!isAlone || !store.canUpscale)
    }
}
