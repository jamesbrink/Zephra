import SwiftUI
import ZephraStyle

/// A surface that is not built yet: its name, its mark, and the one fact the snapshot already
/// knows about it.
///
/// It exists so the four screens are real files with real content from the first commit —
/// each one is replaced from the inside as its surface is built, and the tab bar, the paired
/// state and the frozen previews are all exercised meanwhile.
struct SurfacePlaceholder: View {
    /// The surface's name, as the tab says it.
    let title: String
    /// The SF Symbol standing for it.
    let symbol: String
    /// The one line the snapshot can already fill in, or nil where there is no Mac answering.
    let fact: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(fact ?? "Waiting for your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, MobileChrome.sideMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvasBackground)
    }
}

#Preview("Surface") {
    SurfacePlaceholder(title: "Canvas", symbol: "photo.on.rectangle.angled", fact: "Ready")
}
