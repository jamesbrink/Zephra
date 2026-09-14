import SwiftUI
import ZephraStyle

/// Large text scrolls the complete composer; ordinary sizes keep it beside the live canvas.
struct CanvasLayout: View {
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(\.dynamicTypeSize) private var typeSize

    @Environment(MobileSelection.self) private var selection

    var body: some View {
        if typeSize >= .xxLarge || selection.capsuleIsExpanded {
            ScrollView {
                VStack(spacing: 12) {
                    if !selection.promptIsFocused {
                        picture.frame(height: 180)
                    }
                    if typeSize >= .xxLarge {
                        ModelMenu()
                            .padding(.horizontal, MobileChrome.sideMargin)
                    }
                    PromptCapsule()
                }
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            picture
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) { PromptCapsule() }
        }
    }
    private var picture: some View {
        CanvasPicture()
            .environment(dispatch.hosts.visible?.catalog ?? dispatch.hosts.catalog)
            .padding(.horizontal, MobileChrome.sideMargin)
    }
}
