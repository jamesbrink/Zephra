import SwiftUI
import ZephraEngine

/// Watches the engine's state from the window and posts the notices its transitions are
/// worth. The saved-image notice is not here: the store announces a save through
/// `onImageSaved`, which the composition root wires (`ZephraApp+Library`).
struct BackgroundNoticeObserver: ViewModifier {
    @Environment(GenerationStore.self) private var store

    func body(content: Content) -> some View {
        content.onChange(of: store.state) { old, new in
            // The model whose state moved, which is the one in use; a picture's choice may
            // have moved `descriptor` elsewhere meanwhile.
            let model = (store.modelInUse ?? store.descriptor).fullName
            if let notice = BackgroundNotice.transition(from: old, to: new, model: model) {
                BackgroundNotices.post(notice)
            }
        }
    }
}

extension View {
    /// Posts a notification when a download finishes or fails while Zephra is in the background.
    func postingBackgroundNotices() -> some View { modifier(BackgroundNoticeObserver()) }
}
