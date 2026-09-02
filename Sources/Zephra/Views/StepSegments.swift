import SwiftUI

/// One thin segment per denoising step, laid across the top edge of the prompt capsule and
/// filled left to right as the steps land.
///
/// Deliberately unanimated: each segment is a step that actually happened, so it appears the
/// instant that step reports, and a smoothed bar would be a prettier lie.
struct StepSegments: View {
    /// How many steps this generation will run.
    let total: Int
    /// How many of them have finished.
    let completed: Int
    /// Whether a generation is running at all; segments are invisible the rest of the time.
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Rectangle()
                    .fill(index < completed ? AnyShapeStyle(Color.safelight) : AnyShapeStyle(.quaternary))
            }
        }
        .frame(height: 3)
        .opacity(isRunning ? 1 : 0)
        .accessibilityElement()
        .accessibilityLabel("Step \(completed) of \(total)")
    }
}

#Preview("Mid generation") {
    StepSegments(total: 9, completed: 4, isRunning: true)
        .frame(width: 320)
        .padding()
}
