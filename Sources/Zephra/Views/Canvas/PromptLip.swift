import SwiftUI
import ZephraCore
import ZephraEngine

/// The sliver left at the bottom edge once the prompt has tucked away: the run's step segments,
/// so progress keeps showing, and a chevron that brings the capsule back.
///
/// Drawn as the capsule's own top edge — same material, same radius, same hairline — because it
/// reads as the capsule having slid down rather than as a second, unrelated control.
struct PromptLip: View {
    /// How tall the lip stands above the window's bottom edge.
    static let height: CGFloat = 22

    /// `PromptCapsule`'s own `maxWidth` sits inside `CanvasOverlay`'s horizontal padding on
    /// each side, so its true width tops out at the one minus twice the other — the same figure
    /// the lip needs to sit flush beneath it.
    private static let width: CGFloat = CanvasOverlay.maxWidth - 2 * CanvasOverlay.horizontalPadding

    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(GenerationStore.self) private var store

    var body: some View {
        Button {
            workspace.promptTucked = false
        } label: {
            VStack(spacing: 0) {
                // Inset by the radius, as on the capsule, so the lip's corners clip nothing.
                StepSegments(progress: store.stepProgress)
                    .padding(.horizontal, ZephraChrome.capsuleRadius)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: Self.width)
        .frame(height: Self.height)
        .background(.regularMaterial)
        .clipShape(shape)
        .overlay { shape.strokeBorder(ZephraChrome.hairline, lineWidth: 1) }
        // Invisible while the prompt is showing, so it never steals a click meant for the
        // capsule sitting on top of it, or for the picture behind both.
        .allowsHitTesting(workspace.promptTucked)
        .help("Show the prompt")
        .accessibilityLabel("Show the prompt")
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: ZephraChrome.capsuleRadius,
            topTrailingRadius: ZephraChrome.capsuleRadius,
            style: .continuous
        )
    }
}

#Preview("Lip") {
    PromptLip()
        .frame(width: 900)
        .background(Color.canvasBackground)
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("Lip mid generation") {
    PromptLip()
        .frame(width: 900)
        .background(Color.canvasBackground)
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(
                phase: .denoising(step: 4, of: 9),
                fraction: 0.44,
                secondsPerStep: 2.1
            ))
        ))
}
