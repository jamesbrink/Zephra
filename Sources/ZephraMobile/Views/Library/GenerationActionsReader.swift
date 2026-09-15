import SwiftUI

/// Reusing a picture fills the composer and closes the viewer that offered the action.
struct GenerationActionsReader: ViewModifier {
    @Environment(PromptDraft.self) private var draft
    @Environment(MobileSelection.self) private var selection
    @Environment(ReferenceIntent.self) private var reference

    func body(content: Content) -> some View {
        content.environment(\.reuseImageSettings) { entry in
            guard draft.reuse(entry) else { return }
            reference.clear()
            selection.tab = .canvas
            selection.expandCapsule()
        }
    }
}
