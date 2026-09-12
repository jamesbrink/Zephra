import SwiftUI
import ZephraEngine
import ZephraStyle

/// The strip across the top of the window saying a newer Zephra is published, and how far
/// along fetching it is once somebody has pressed Update Now.
///
/// A strip rather than an alert: an update is not a question that has to be answered before
/// the window can be used again, and a modal sheet over somebody's half-written prompt for a
/// thing that can wait is exactly the interruption people learn to switch off. It sits in
/// `RootView`'s top safe area, so the sidebar, the panes and the inspector lay out under it
/// rather than behind it.
///
/// The progress bar is determinate and there is no repeating animation anywhere in it: the GPU
/// belongs to the model while it works, and a spinning indicator over a streamed step is the
/// thing that reset an M4 mini's GPU (`make lint-layers` enforces the ban).
///
/// The checker is optional in the environment for the reason `CompanionHost` is: a frozen
/// preview build and the `#Preview`s below have none, and drawing nothing is the right answer
/// there rather than a crash.
struct UpdateBanner: View {
    @Environment(UpdateChecker.self) private var updates: UpdateChecker?

    var body: some View {
        if let updates, updates.showsBanner {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(updates.phase.sentence)
                    .font(.callout)
                    .lineLimit(1)
                if case .downloading(_, let fraction) = updates.phase {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 160)
                }
                Spacer(minLength: 12)
                UpdateBannerActions()
            }
            .padding(.horizontal, 16)
            .frame(height: ZephraChrome.barHeight)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ZephraChrome.hairline)
                    .frame(height: 1)
            }
        }
    }
}

#Preview("Available") {
    UpdateBanner()
        .frame(width: 900)
        .environment(UpdateChecker.frozen(.available(UpdateBannerActions.sample)))
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("Downloading") {
    UpdateBanner()
        .frame(width: 900)
        .environment(UpdateChecker.frozen(.downloading(UpdateBannerActions.sample, fraction: 0.42)))
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("Failed") {
    UpdateBanner()
        .frame(width: 900)
        .environment(UpdateChecker.frozen(.failed(reason: "Zephra could not reach the update server.")))
        .environment(GenerationStore.preview(state: .ready))
}
