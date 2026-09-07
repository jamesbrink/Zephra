import SwiftUI
import ZephraEngine

/// The seed on the capsule, spelled as Settings says, and the way to type one in: a click
/// opens `SeedEntryPopover` over it.
///
/// Split from `SeedControl` so the spelling can be read from the environment without the
/// control taking a fourth stored property. The tooltip carries the whole number whatever the
/// spelling, because the number is the exact seed and what every file name carries; under the
/// decimal setting it repeats the chip, which costs nothing.
struct SeedLabel: View {
    /// Whether the entry popover is up; the control owns it so a shuffle can close it.
    @Binding var isEntering: Bool
    @Environment(GenerationStore.self) private var store
    @Environment(\.seedFormat) private var format

    var body: some View {
        Button {
            isEntering = true
        } label: {
            Text(format.label(store.settings.seed))
                .font(.callout)
                .monospaced()
                .foregroundStyle(.secondary)
                .fixedSize()
                .padding(.horizontal, 4)
        }
        .buttonStyle(.accessoryBar)
        .help("Seed \(String(store.settings.seed)). Click to type one in.")
        .accessibilityLabel("Seed \(String(store.settings.seed))")
        .popover(isPresented: $isEntering, arrowEdge: .top) {
            SeedEntryPopover(isPresented: $isEntering, initialText: format.exactText(store.settings.seed))
        }
    }
}

#Preview("Seed label") {
    SeedLabel(isEntering: .constant(false))
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}
