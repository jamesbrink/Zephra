import SwiftUI
import ZephraEngine
import ZephraStyle

/// Everything that floats over the picture, stacked up from the bottom edge: a save notice when
/// there is one, the caption of the image being looked at, and the prompt capsule.
///
/// Nothing under the capsule any more. The strip of this run's seeds used to sit there and push
/// the capsule up the moment a run started, so the picture jumped every time you pressed
/// Generate. The same squares are in the sidebar's session timeline now, beside the card that
/// says how far along the run is.
struct CanvasOverlay: View {
    /// How wide the stack may grow: controls wrap within this when their settings and actions
    /// cannot share a row.
    static let maxWidth: CGFloat = 736
    /// The air on each side, inside that width.
    static let horizontalPadding: CGFloat = 28

    var body: some View {
        VStack(spacing: 14) {
            SaveNotice()
            OpenFailureNotice()
            PromptCaption()
            PromptCapsule()
        }
        .padding(.horizontal, Self.horizontalPadding)
        // A little more than the sidebar's foot, so the capsule floats rather than sits.
        .padding(.bottom, 26)
        .frame(maxWidth: Self.maxWidth)
    }
}

#Preview("Overlay") {
    CanvasOverlay()
        .padding(.top, 60)
        .frame(width: 900)
        .background(Color.canvasBackground)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}
