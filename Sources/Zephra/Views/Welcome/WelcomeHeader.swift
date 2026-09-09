import SwiftUI

/// The chooser's top: the app's mark, what the screen is for, and the one thing worth knowing
/// before a model is picked.
///
/// The serif deliberately stays out of it. `CanvasEmptyState` says the empty canvas is the one
/// place it belongs, and a second use would make it decoration rather than a mark.
struct WelcomeHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            Text("Choose your first model")
                .font(.title)
            Text(
                "Every model runs on this Mac, and nothing you make leaves it. "
                    + "You can add the others later."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }
}

#Preview("Header") {
    WelcomeHeader()
        .frame(width: 720)
        .background(Color.canvasBackground)
}
