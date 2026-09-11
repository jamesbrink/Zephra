import SwiftUI
import ZephraEngine
import ZephraStyle

/// Slides `CanvasOverlay` down by its own height, minus the lip, when the prompt is tucked away.
///
/// An offset rather than a transition: swapping the overlay out with an `if` would tear down
/// `PromptEditor` along with it, and with it the text view's undo stack and scroll position.
/// Offsetting instead just moves the same view off the bottom edge.
struct PromptTuckOverlay: View {
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var overlayHeight: CGFloat = 0

    private var tucked: Bool { workspace.promptTucked }

    var body: some View {
        ZStack(alignment: .bottom) {
            CanvasOverlay()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { overlayHeight = $0 }
                .offset(y: tucked ? overlayHeight - PromptLip.height : 0)
                .allowsHitTesting(!tucked)
                .accessibilityHidden(tucked)
            PromptLip()
                .opacity(tucked ? 1 : 0)
        }
        .animation(reduceMotion ? nil : .snappy, value: tucked)
    }
}

#Preview("Showing") {
    PromptTuckOverlay()
        .frame(width: 900, height: 500)
        .background(Color.canvasBackground)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}

#Preview("Tucked") {
    let workspace = WorkspaceSelection(pane: .canvas)
    workspace.promptTucked = true
    return PromptTuckOverlay()
        .frame(width: 900, height: 500)
        .background(Color.canvasBackground)
        .environment(ImageCache())
        .environment(workspace)
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}
