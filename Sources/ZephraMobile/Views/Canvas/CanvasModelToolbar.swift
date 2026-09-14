import SwiftUI

/// Large model names belong in the scrollable canvas when text grows.
struct CanvasModelToolbar: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    @Environment(MobileSelection.self) private var selection

    func body(content: Content) -> some View {
        content.toolbar {
            if selection.capsuleIsExpanded {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        selection.collapseCapsule()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Finish editing")
                }
            }
            if typeSize < .xxLarge && !selection.capsuleIsExpanded {
                ToolbarItem(placement: .topBarTrailing) { ModelMenu() }
            }
        }
    }
}
