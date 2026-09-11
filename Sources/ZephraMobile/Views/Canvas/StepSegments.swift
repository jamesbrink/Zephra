import SwiftUI
import ZephraStyle

/// One thin segment per denoising step, laid across the top edge of the capsule and filled
/// left to right as the steps land on the Mac.
///
/// Deliberately unanimated, exactly as on the Mac: each segment is a step that actually
/// happened, so it appears the instant that step reports, and a smoothed bar would be a
/// prettier lie.
struct StepSegments: View {
    /// How far the run has got, and how many steps it has.
    let progress: StepProgress

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(progress.total, 1), id: \.self) { index in
                Rectangle()
                    .fill(
                        index < progress.completed
                            ? AnyShapeStyle(Color.safelight) : AnyShapeStyle(.quaternary))
            }
        }
        .frame(height: 3)
        .opacity(progress.isRunning ? 1 : 0)
        .accessibilityElement()
        .accessibilityLabel("Step \(progress.completed) of \(progress.total)")
    }
}

#Preview("Mid generation") {
    StepSegments(progress: StepProgress(completed: 4, total: 9, isRunning: true))
        .padding()
}
